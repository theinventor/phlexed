class ProfilesController < ApplicationController
  def show
    render Profile::ShowView.new(user: current_user_stub)
  end

  def edit
    render Profile::EditView.new(user: current_user_stub)
  end

  def update
    redirect_to profile_path, notice: "Profile updated."
  end

  private

  def current_user_stub
    OpenStruct.new(
      name: "Troy",
      email: "troy@example.com",
      bio: "Rails developer building phlexed.",
      created_at: 6.months.ago,
      last_seen_at: 2.hours.ago
    )
  end
end
