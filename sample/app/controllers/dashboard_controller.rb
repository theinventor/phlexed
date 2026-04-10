class DashboardController < ApplicationController
  def index
    @stats = { users: 1204, revenue: "12,400", conversion: "4.2%" }
    @activities = [] # wire up to a real Activity model later
  end
end
