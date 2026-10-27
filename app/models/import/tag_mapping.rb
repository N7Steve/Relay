class Import::TagMapping < Import::Mapping
  class << self
    def mappables_by_key(import)
      unique_values = if import.is_a?(QifImport)
        import.row_tags
      else
        import.rows.map(&:tags_list).flatten.uniq
      end

      tags = import.personal_tags.where(name: unique_values).index_by(&:name)

      unique_values.index_with { |value| tags[value] }
    end
  end

  def selectable_values
    family_tags = import.personal_tags.alphabetically.map { |tag| [ tag.name, tag.id ] }

    unless key.blank?
      family_tags.unshift [ "Add as new tag", CREATE_NEW_KEY ]
    end

    family_tags
  end

  def requires_selection?
    false
  end

  def values_count
    import.rows.map(&:tags_list).flatten.count { |tag| tag == key }
  end

  def mappable_class
    Tag
  end

  def create_mappable!
    return unless creatable?

    self.mappable = import.personal_tags.find_by(name: key) || import.personal_tags.create!(name: key, user: import.tag_owner)
    save!
  end
end
