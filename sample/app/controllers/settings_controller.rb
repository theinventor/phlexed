class SettingsController < ApplicationController
  def index
    @user = current_user_stub
  end

  def update
    redirect_to settings_path, notice: "Settings saved."
  end

  private

  def current_user_stub
    OpenStruct.new(
      name: "Troy",
      email: "troy@example.com",
      bio: "Rails developer building phlexed.",
      notifications_enabled: true
    )
  end
end
