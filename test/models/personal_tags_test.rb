require "test_helper"

class PersonalTagsTest < ActiveSupport::TestCase
  test "editing personal tags preserves tags applied by another account participant" do
    member, admin = users(:family_member), users(:family_admin)
    mine = member.tags.create!(family: member.family, name: "Mine")
    theirs = admin.tags.create!(family: admin.family, name: "Theirs")
    transaction = transactions(:one)
    transaction.tags = [ theirs ]
    Current.set(session: member.sessions.create!) do
      transaction.update!(tag_ids: [ mine.id ])
      assert_equal [ mine.id, theirs.id ].sort, transaction.reload.tag_ids.sort
      transaction.update!(tag_ids: [])
      assert_equal [ theirs.id ], transaction.reload.tag_ids
      unknown = admin.tags.create!(family: admin.family, name: "Other private tag")
      assert_raises(ActiveRecord::RecordNotFound) { transaction.tag_ids = [ unknown.id ] }
    end
  end

  test "member import maps only owned accounts and personal tags and cannot create global categories" do
    member = users(:family_member)
    import = member.family.imports.create!(type: "TransactionImport", user: member)
    assert_not_includes import.target_accounts, accounts(:depository)
    mapping = import.mappings.create!(type: "Import::CategoryMapping", key: "Unrecognized", create_when_empty: true)
    assert_raises(Import::MappingError) { mapping.create_mappable! }
    assert_raises(Import::MappingError) { import.authorize_member_import! }
    mapping.destroy!
    tag_mapping = import.mappings.create!(type: "Import::TagMapping", key: "Imported tag", create_when_empty: true)
    tag_mapping.create_mappable!
    assert_equal member, tag_mapping.reload.mappable.user
    import.update!(account: accounts(:depository))
    assert_raises(Import::MappingError) { import.authorize_member_import! }
  end
  test "member CSV publishing uses an owned account and existing global categories" do
    member = users(:family_member)
    account = member.family.accounts.create!(owner: member, name: "CSV checking", accountable: Depository.new, balance: 0, currency: "USD")
    import = member.family.imports.create!(type: "TransactionImport", user: member, account: account,
      date_format: "%Y-%m-%d", date_col_label: "date", amount_col_label: "amount", name_col_label: "name",
      category_col_label: "category", tags_col_label: "tags",
      raw_file_str: "date,amount,name,category,tags\n2026-10-01,20,Coffee,Food & Drink,Personal\n")
    import.generate_rows_from_csv
    import.sync_mappings
    assert_not import.mappings.categories.first.create_when_empty
    assert_no_difference("Category.count") { import.publish }
    assert import.reload.complete?, import.error
    entry = import.entries.sole
    assert_equal account, entry.account
    assert_equal categories(:food_and_drink), entry.transaction.category
    assert_equal member, entry.transaction.tags.sole.user
  end
  test "queued member imports fail closed if the actor is removed or account ownership changes" do
    member = users(:family_member)
    account = member.family.accounts.create!(owner: member, name: "Revoked checking", accountable: Depository.new, balance: 0, currency: "USD")
    import = member.family.imports.create!(type: "TransactionImport", user: member, account: account)
    account.update!(owner: users(:family_admin))
    assert_raises(Import::MappingError) { import.reload.authorize_member_import! }
    import.update!(user: nil)
    assert import.actor_bound?
    assert_raises(Import::MappingError) { import.authorize_member_import! }
  end
  test "tag filters distinguish identical names belonging to different users" do
    member, admin = users(:family_member), users(:family_admin)
    mine = member.tags.create!(family: member.family, name: "Same name")
    theirs = admin.tags.create!(family: admin.family, name: "Same name")
    account = accounts(:depository)
    first = account.entries.create!(name: "Own tagged", date: Date.current, amount: 10, currency: "USD", entryable: Transaction.new(tags: [ mine ]))
    second = account.entries.create!(name: "Other tagged", date: Date.current, amount: 10, currency: "USD", entryable: Transaction.new(tags: [ theirs ]))
    scope = Transaction::Search.new(member.family, filters: { tags: [ "Same name" ] }, user: member).transactions_scope
    assert_includes scope, first.transaction
    assert_not_includes scope, second.transaction
  end
  test "MCP organization operations give members personal tags but read-only global categories" do
    member = users(:family_member)
    operations = Api::DailyOperations.new(access: Api::Access.new(user: member, scopes: [ "read_write" ]))
    result = operations.call("create_tag", { "name" => "MCP personal", "idempotency_key" => SecureRandom.uuid })
    assert_equal member, Tag.find(result.fetch("id")).user
    other = users(:family_admin).tags.create!(family: member.family, name: "Private")
    assert_raises(ActiveRecord::RecordNotFound) do
      operations.call("update_tag", { "tag_id" => other.id, "name" => "Forbidden", "idempotency_key" => SecureRandom.uuid })
    end
    assert_raises(Api::Access::Forbidden) do
      operations.call("create_category", { "name" => "Forbidden", "idempotency_key" => SecureRandom.uuid })
    end
  end
  test "rule actions cannot introduce another users personal tag through a forged reference" do
    member = users(:family_member)
    mine = member.tags.create!(family: member.family, name: "Own rule tag")
    theirs = users(:family_admin).tags.create!(family: member.family, name: "Private rule tag")
    rule = member.family.rules.new(resource_type: "transaction")
    Current.set(session: member.sessions.create!) do
      action = rule.actions.build(action_type: "set_transaction_tags", value: theirs.id)
      assert_not action.valid?
      action.value = mine.id
      assert action.valid?, action.errors.full_messages.to_sentence
    end
  end
end
