module PersonallyTaggable
  extend ActiveSupport::Concern

  def tag_ids=(ids)
    actor = Current.user
    return super unless actor

    personal = actor.family.personal_tags_for(actor)
    selected = Array(ids).reject(&:blank?).map(&:to_s)
    existing_foreign = persisted? ? tags.where.not(id: personal.select(:id)).pluck(:id) : []
    allowed = personal.where(id: selected).pluck(:id) + existing_foreign
    if (selected - allowed).any?
      raise ActiveRecord::RecordNotFound, "Tag is not available to this user"
    end
    super(allowed.uniq)
  end
end
