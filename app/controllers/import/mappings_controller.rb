class Import::MappingsController < ApplicationController
  before_action :set_import

  def update
    mapping = @import.mappings.find(params[:id])

    mapping.update! \
      create_when_empty: create_when_empty,
      mappable: mappable,
      value: mapping_params[:value]

    redirect_back_or_to import_confirm_path(@import)
  end

  private
    def mapping_params
      params.require(:import_mapping).permit(:type, :key, :mappable_id, :mappable_type, :value)
    end

    def set_import
      @import = Import.accessible_to(Current.user).find(params[:import_id])
    end

    def mappable
      mapping = @import.mappings.find(params[:id])
      scope = case mapping
      when Import::AccountMapping then @import.target_accounts
      when Import::TagMapping then @import.personal_tags
      when Import::CategoryMapping then Current.family.categories
      end
      scope&.find(mapping_params[:mappable_id]) if mapping_params[:mappable_id].present? && !create_when_empty
    end

    def create_when_empty
      mapping = @import.mappings.find(params[:id])
      creating = mapping_params[:mappable_id] == Import::Mapping::CREATE_NEW_KEY
      if creating && !Current.user.admin? && !mapping.is_a?(Import::TagMapping)
        raise ActiveRecord::RecordNotFound
      end
      creating
    end
end
