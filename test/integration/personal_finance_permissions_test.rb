require "test_helper"

class PersonalFinancePermissionsTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:family_member)
    @admin = users(:family_admin)
    sign_in @member
  end

  test "member reads categories but cannot create update delete or bootstrap them" do
    get categories_url
    assert_response :success
    assert_select "a[href=?]", new_category_path, count: 0
    category = categories(:food_and_drink)
    assert_no_difference("Category.count") do
      post categories_url, params: { category: { name: "Forbidden" } }
      assert_redirected_to accounts_url
      delete category_url(category)
      assert_redirected_to accounts_url
      post bootstrap_categories_url
      assert_redirected_to accounts_url
    end
    original = category.name
    patch category_url(category), params: { category: { name: "Forbidden" } }
    assert_redirected_to accounts_url
    assert_equal original, category.reload.name
  end

  test "tags are personal even between members of the same family" do
    mine = @member.tags.create!(family: @member.family, name: "Personal")
    theirs = @admin.tags.create!(family: @admin.family, name: "Personal")
    get tags_url
    assert_response :success
    assert_select "##{dom_id(mine)}", count: 1
    assert_select "##{dom_id(theirs)}", count: 0
    patch tag_url(theirs), params: { tag: { name: "Forbidden" } }
    assert_response :not_found
    delete tag_url(theirs)
    assert_response :not_found
    post tags_url, params: { tag: { name: "Created by member" } }
    assert_equal @member, Tag.find_by!(name: "Created by member").user
  end

  test "member imports have an actor and cannot target another owners account" do
    own = @member.family.accounts.create!(owner: @member, name: "Member checking", accountable: Depository.new, balance: 0, currency: "USD")
    post imports_url, params: { import: { type: "TransactionImport", account_id: own.id } }
    import = Import.order(created_at: :desc).first
    assert_equal @member, import.user
    assert_equal own, import.account
    post imports_url, params: { import: { type: "TransactionImport", account_id: accounts(:depository).id } }
    assert_response :not_found
    post imports_url, params: { import: { type: "CategoryImport" } }
    assert_response :forbidden
    other_import = @admin.family.imports.create!(type: "TransactionImport", user: @admin)
    get import_upload_url(other_import)
    assert_response :not_found
  end
  test "REST catalogs are personal and member category writes are forbidden" do
    @member.api_keys.active.destroy_all
    key = ApiKey.create!(user: @member, name: "Personal test", key: ApiKey.generate_secure_key, scopes: [ "read_write" ], source: "web")
    headers = { "X-Api-Key" => key.plain_key }
    theirs = @admin.tags.create!(family: @admin.family, name: "Private admin tag")
    post api_v1_tags_url, params: { tag: { name: "API personal tag" } }, headers: headers
    assert_response :created
    mine = Tag.find(JSON.parse(response.body).fetch("id"))
    assert_equal @member, mine.user
    get api_v1_tags_url, headers: headers
    assert_equal [ mine.id ], JSON.parse(response.body).map { |tag| tag.fetch("id") }
    patch api_v1_tag_url(theirs), params: { tag: { name: "Forbidden" } }, headers: headers
    assert_response :not_found
    post api_v1_categories_url, params: { category: { name: "Forbidden" } }, headers: headers
    assert_response :forbidden
  end
  test "shared transaction shows other users tags without including them in the personal picker" do
    entry = transactions(:one).entry
    entry.account.account_shares.find_or_create_by!(user: @member) { |share| share.permission = "read_write" }
    mine = @member.tags.create!(family: @member.family, name: "Member picker tag")
    theirs = @admin.tags.create!(family: @admin.family, name: "Visible shared tag")
    entry.transaction.tags = [ theirs ]
    get transaction_url(entry)
    assert_response :success
    assert_includes response.body, theirs.name
    assert_select "[data-tag-select-target=option][data-tag-id=?]", mine.id, count: 1
    assert_select "[data-tag-select-target=option][data-tag-id=?]", theirs.id, count: 0
  end
  test "bulk personal tagging preserves other participants tags and excludes inaccessible accounts" do
    mine = @member.tags.create!(family: @member.family, name: "My bulk tag")
    theirs = @admin.tags.create!(family: @admin.family, name: "Other participants tag")
    shared = accounts(:depository).entries.create!(name: "Shared bulk", date: Date.current, amount: 10, currency: "USD", entryable: Transaction.new(tags: [ theirs ]))
    private_entry = accounts(:other_asset).entries.create!(name: "Private bulk", date: Date.current, amount: 10, currency: "USD", entryable: Transaction.new)
    post transactions_bulk_update_url, params: { bulk_update: { entry_ids: [ shared.id, private_entry.id ], tag_ids: [ mine.id ] } }
    assert_redirected_to transactions_url
    assert_equal [ mine.id, theirs.id ].sort, shared.reload.transaction.tag_ids.sort
    assert_empty private_entry.reload.transaction.tag_ids
  end
  test "copying a shared transaction only preselects the actors personal tags" do
    entry = transactions(:one).entry
    theirs = @admin.tags.create!(family: @admin.family, name: "Other persons tag")
    entry.transaction.tags = [ theirs ]
    get new_transaction_url(duplicate_entry_id: entry.id)
    assert_response :success
    get new_scheduled_payment_url(from_entry_id: entry.id)
    assert_response :success
  end
end
