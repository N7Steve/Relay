class Tag::DropdownsController < ApplicationController
  def show
    @entry = Current.accessible_entries.where(entryable_type: "Transaction").find(params[:entry_id])
    @transaction = @entry.transaction
    @tags = Current.family.personal_tags_for(Current.user).alphabetically
    @selected_tag_ids = @transaction.tag_ids.to_set
  end
end
