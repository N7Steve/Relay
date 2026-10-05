class AccountsController < ApplicationController
  include StreamExtensions

  before_action :set_account, only: %i[show sparkline sync set_default remove_default]
  before_action :set_manageable_account, only: %i[
    toggle_active toggle_archived
    destroy unlink confirm_unlink select_provider
  ]
  before_action :ensure_linked_account, only: %i[confirm_unlink unlink]
  include Periodable

  def index
    @accessible_account_ids = Current.user.accessible_accounts.pluck(:id)
    @manual_accounts = family.accounts
          .listable_without_active_connector
          .where(id: @accessible_account_ids)
          .with_attached_logo
          .includes(:accountable, :account_providers)
          .order(:name)
    @enable_banking_items = visible_provider_items(family.enable_banking_items.ordered.with_attached_logo)

    preload_latest_sync_metadata_for_index!

    # Build sync stats maps for all providers
    build_sync_stats_maps

    # Prevent Turbo Drive from caching this page to ensure fresh account lists
    expires_now
    render layout: "settings"
  end

  def new
    # Get all registered providers with any credentials configured
    @provider_configs = Provider::Factory.registered_adapters.flat_map do |adapter_class|
      adapter_class.connection_configs(family: family)
    end
  end

  def sync_all
    family.sync_later
    redirect_to accounts_path, notice: t("accounts.sync_all.syncing")
  end

  def sidebar
    @mobile_sidebar = ActiveModel::Type::Boolean.new.cast(params[:mobile])
    active_account_id = params[:active_account_id].presence
    @sidebar_active_account_id = if active_account_id
      Current.user.accessible_accounts.where(id: active_account_id).pick(:id)&.to_s
    end

    render layout: false
  end

  def show
    @chart_view = params[:chart_view] || "balance"
    @tab = params[:tab]
    # One reference date for everything on the page that is date-sensitive:
    # the chart, its projection, the cards and the Schedule tab. Read
    # separately, a render crossing midnight shows a chart projecting from one
    # date beside a table shaded against another.
    @as_of = Date.current
    @accessible_account_ids = Current.user.accessible_accounts.pluck(:id).to_set
    @q = params.fetch(:q, {}).permit(:search, :uncategorized, status: [])
    entries = @account.entries.excluding_split_parents.search(@q).reverse_chronological.includes(:entryable)
    if statement_tab_active?
      build_statement_tab_data
      return render_statement_tab_frame if statement_tab_frame_request?
    end

    # Only for a response that will actually show the chart card. The payload
    # runs the schedule and the projection; a Turbo frame request for the
    # activity feed's `entries` frame (its pagination) renders the whole page
    # and keeps one frame, so building it there was a full simulation per page
    # turn for nothing. Same reasoning as the statements-frame return above.
    #
    # The chart and the Schedule tab's forecast card read the same projection,
    # so it is built once here and handed to both.
    @loan_projection = @account.loan.payoff_projection(as_of: @as_of) if @account.accountable.is_a?(Loan)
    @loan_chart = loan_payoff_chart(@account, as_of: @as_of, period: @period, projection: @loan_projection) if chart_card_requested?

    per_page = safe_per_page(stored_per_page_default)
    store_per_page!(per_page) if params[:per_page].present?

    @pagy, @entries = pagy(
      entries,
      limit: per_page,
      params: request.query_parameters.except("tab").merge("tab" => "activity")
    )

    # Preload transfer associations only for Transaction entries
    txn_entryables = @entries.filter_map { |e| e.entryable if e.entryable_type == "Transaction" }
    ActiveRecord::Associations::Preloader.new(
      records: txn_entryables,
      associations: {
        transfer_as_outflow: { inflow_transaction: { entry: :account } },
        transfer_as_inflow: { outflow_transaction: { entry: :account } }
      }
    ).call

    Transaction::ActivitySecurityPreloader.new(@entries).preload

    # The preload and split-parent lookup below are intentionally scoped to the
    # current page (@entries) — only this page is rendered, so a child entry
    # whose split parent sits on another page deliberately won't resolve it.
    transactions = @entries.filter_map { |e| e.entryable if e.transaction? }
    if transactions.any?
      ActiveRecord::Associations::Preloader.new(
        records: transactions,
        associations: [ :transfer_as_inflow, :transfer_as_outflow, :category, :merchant, :tags ]
      ).call
    end

    trades = @entries.filter_map { |e| e.entryable if e.entryable_type == "Trade" }
    if trades.any?
      ActiveRecord::Associations::Preloader.new(
        records: trades,
        associations: [ :security ]
      ).call
    end

    entry_ids = @entries.map(&:id)
    @split_parent_entry_ids = if entry_ids.any?
      Entry.where(parent_entry_id: entry_ids).distinct.pluck(:parent_entry_id).to_set
    else
      Set.new
    end

    # Load split parent entries for grouped display (only when grouping is enabled)
    @split_parents = if Current.user.show_split_grouped?
      split_parent_ids = @entries.filter_map(&:parent_entry_id).uniq
      if split_parent_ids.any?
        Entry.where(id: split_parent_ids)
             .includes(:account, entryable: [ :category, :merchant ])
             .index_by(&:id)
      else
        {}
      end
    else
      {}
    end

    @activity_feed_data = Account::ActivityFeedData.new(@account, @entries, split_parents: @split_parents)
  end

  def sync
    unless @account.syncing?
      if @account.linked? && ExternalAccess.enabled?(:bank_sync)
        # Sync all provider items for this account
        # Each provider item will trigger an account sync when complete
        @account.account_providers.each do |account_provider|
          item = account_provider.adapter&.item
          next unless item && !item.syncing?

          item.sync_later
        end
      else
        # Manual accounts just need balance materialization
        @account.sync_later
      end
    end

    redirect_to account_path(@account)
  end

  def sparkline
    etag_key = @account.family.build_cache_key("#{@account.id}_sparkline_#{Account::Chartable::SPARKLINE_CACHE_VERSION}", invalidate_on_data_updates: true)

    # Short-circuit with 304 Not Modified when the client already has the latest version.
    # We defer the expensive series computation until we know the content is stale.
    if stale?(etag: etag_key, last_modified: @account.family.latest_sync_completed_at)
      @sparkline_series = @account.sparkline_series
      render layout: false
    end
  end

  def toggle_active
    active_param = params[:active] || params.dig(:account, :active)
    if active_param.present?
      cast_value = ActiveModel::Type::Boolean.new.cast(active_param)
      cast_value ? @account.enable! : @account.disable!
    else
      if @account.active?
        @account.disable!
      elsif @account.disabled?
        @account.enable!
      end
    end
    redirect_to accounts_path
  end

  def toggle_archived
    archived_param = params[:archived] || params.dig(:account, :archived)
    if archived_param.present?
      cast_value = ActiveModel::Type::Boolean.new.cast(archived_param)
      @account.update!(archived: cast_value)
    else
      @account.toggle!(:archived)
    end
    redirect_to accounts_path
  end

  def set_default
    unless @account.eligible_for_transaction_default?
      redirect_to accounts_path, alert: t("accounts.set_default.depository_only")
      return
    end

    Current.user.update!(default_account: @account)
    redirect_to accounts_path
  end

  def remove_default
    Current.user.update!(default_account: nil)
    redirect_to accounts_path
  end

  def destroy
    if @account.linked?
      redirect_to account_path(@account), alert: t("accounts.destroy.cannot_delete_linked")
    else
      begin
        @account.destroy_later
        redirect_to accounts_path, notice: t("accounts.destroy.success", type: @account.accountable_type)
      rescue => e
        Rails.logger.error "Failed to schedule account #{@account.id} for deletion: #{e.message}"
        redirect_to accounts_path, alert: t("accounts.destroy.failed")
      end
    end
  end

  def confirm_unlink
  end

  def unlink
    begin
      Account.transaction do
        # Detach holdings from provider links before destroying them
        provider_link_ids = @account.account_providers.pluck(:id)
        if provider_link_ids.any?
          Holding.where(account_provider_id: provider_link_ids).update_all(account_provider_id: nil)
        end

        @account.account_providers.reload.destroy_all
      end

      redirect_to accounts_path, notice: t("accounts.unlink.success")
    rescue ActiveRecord::RecordInvalid => e
      redirect_to account_path(@account), alert: t("accounts.unlink.error", error: e.message)
    rescue StandardError => e
      Rails.logger.error "Failed to unlink account #{@account.id}: #{e.message}"
      redirect_to account_path(@account), alert: t("accounts.unlink.error", error: t("accounts.unlink.generic_error"))
    end
  end

  def select_provider
    if @account.linked?
      redirect_to account_path(@account), alert: t("accounts.select_provider.already_linked")
      return
    end

    account_type_name = @account.accountable_type

    # Get all available provider configs dynamically for this account type
    provider_configs = Provider::Factory.connection_configs_for_account_type(
      account_type: account_type_name,
      family: family
    )

    # Build available providers list with paths resolved for this specific account
    # Filter out providers that don't support linking to existing accounts
    @available_providers = provider_configs.filter_map do |config|
      next unless config[:existing_account_path].present?
      {
        name: config[:name],
        key: config[:key],
        description: config[:description],
        path: config[:existing_account_path].call(@account.id)
      }
    end

    if @available_providers.empty?
      redirect_to account_path(@account), alert: t("accounts.select_provider.no_providers")
    end
  end

  private
    # Built here rather than in the template: assembling a chart payload is
    # domain work, and `show` asks for it exactly once per request, so there
    # is nothing to memoise.
    #
    # The payload runs the schedule, the projection and a balance query from
    # inputs this app does not fully control: `term_months` and `rate_type`
    # arrive from providers, `start_date` and the rate schedule from the form,
    # balances from sync. A raise in any of them costs the chart, not the page:
    # nil is what the component already takes as "no chart", and the account
    # page then renders exactly as it did before the chart existed. Reported,
    # because a loan silently losing its chart is a bug someone has to see.
    def loan_payoff_chart(account, as_of:, period:, projection: nil)
      return nil unless account.accountable.is_a?(Loan)

      Loan::PayoffChart.new(account.loan, as_of: as_of, period: period, projection: projection).payload
    rescue StandardError => e
      Rails.logger.error("Loan payoff chart failed for account #{account.id}: #{e.class} - #{e.message}")
      LocalDiagnostics.report(e, metadata: { record_type: "Account", record_id: account.id }, source: "controllers/accounts_controller")
      nil
    end

    # A plain visit, or a frame request for one of the two frames the chart
    # card sits inside: the account's container frame and the chart card's own
    # chart_details frame. Any other frame is rendered and then discarded.
    def chart_card_requested?
      return true unless turbo_frame_request?

      request.headers["Turbo-Frame"].in?([
        helpers.dom_id(@account, :container),
        helpers.dom_id(@account, :chart_details)
      ])
    end

    def ensure_linked_account
      return if @account.linked?

      redirect_to account_path(@account), alert: t("accounts.unlink.not_linked")
    end

    def family
      Current.family
    end

    # Shares the "per page" preference with TransactionsController's
    # prev_transaction_page_params so the page size the user picks on either
    # the account activity feed or the global transactions page applies to both.
    def store_per_page!(value)
      Current.session.update!(
        prev_transaction_page_params: Current.session.prev_transaction_page_params.merge("per_page" => value)
      )
    end

    def stored_per_page_default
      Current.session.prev_transaction_page_params["per_page"].presence || 10
    end

    def set_account
      @account = Current.user.accessible_accounts.find(params[:id])
    end

    def set_manageable_account
      @account = Current.user.accessible_accounts.find(params[:id])
      permission = @account.permission_for(Current.user)
      unless permission.in?([ :owner, :full_control ])
        respond_to do |format|
          format.html { redirect_to account_path(@account), alert: t("accounts.not_authorized") }
          format.turbo_stream { stream_redirect_to(account_path(@account), alert: t("accounts.not_authorized")) }
        end
        nil
      end
    end

    def visible_provider_items(items)
      accessible_ids = @accessible_account_ids.to_a

      items.select do |item|
        next true if Current.user.admin?

        account_ids = item.respond_to?(:accounts) ? item.accounts.map(&:id) : []

        # Ownership shows a member their own connection, importantly including
        # one just created that has not synced any accounts yet. It must not
        # widen what they can see: the card renders the item's accounts
        # unfiltered, and is re-rendered by a family-wide broadcast with no
        # viewer, so an owner is shown the card only while every account on it
        # is already accessible to them.
        if item.respond_to?(:owned_by?) && item.owned_by?(Current.user)
          next true if (account_ids - accessible_ids).empty?
        end

        (account_ids & accessible_ids).any?
      end
    end

    def preload_latest_sync_metadata_for_index!
      items = @enable_banking_items.to_a

      accounts = @manual_accounts.to_a
      items.each do |item|
        next unless item.respond_to?(:accounts)
        accounts.concat(item.accounts)
      end
      accounts = accounts.uniq { |account| account.id }

      syncables = items + accounts

      Current.latest_sync_by_syncable = Sync.latest_by_syncable(syncables)
      Current.latest_completed_sync_by_syncable = Sync.latest_completed_by_syncable(syncables)
      Current.syncing_by_syncable = Sync.syncing_by_syncable(syncables)
    end

    def build_statement_tab_data
      return unless statement_tab_active?

      @statement_coverage = AccountStatement::Coverage.for_year(@account, params[:statement_year])
      @account_statements = @account.account_statements.with_attached_original_file.ordered.to_a
      @statement_reconciliation_statuses = AccountStatement.reconciliation_statuses_for(@account_statements, account: @account)
      permission = @account.permission_for(Current.user)
      @can_manage_statements = AccountStatement.statement_manager?(Current.user) &&
        permission.in?([ :owner, :full_control ])
    end

    def statement_tab_frame_request?
      turbo_frame_request? && request.headers["Turbo-Frame"] == helpers.dom_id(@account, :statements_tab)
    end

    def render_statement_tab_frame
      render partial: "accounts/show/statements_frame", locals: statement_tab_locals, layout: false
    end

    def statement_tab_locals
      {
        account: @account,
        coverage: @statement_coverage,
        statements: @account_statements,
        reconciliation_statuses: @statement_reconciliation_statuses,
        can_manage_statements: @can_manage_statements
      }
    end

    def statement_tab_active?
      @tab == "statements"
    end

    # Builds sync stats maps for all provider types to avoid N+1 queries in views
    def build_sync_stats_maps
      @enable_banking_sync_stats_map = @enable_banking_items.to_h do |item|
        latest_sync = Current.latest_sync_by_syncable&.dig([ item.class.base_class.name, item.id ])
        [ item.id, latest_sync&.sync_stats || {} ]
      end
    end
end
