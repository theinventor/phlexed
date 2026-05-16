module Profile
  # Target-state example: this is what /phlexed-build produces.
  # Compare against settings/index.html.erb (which is ERB and awaiting retrofit)
  # to see the before/after dramatic improvement.
  class ShowView < Views::Base
    def initialize(user:)
      @user = user
    end

    def view_template
      h1(class: "text-3xl font-bold mb-6") { "Profile" }

      render PhlexyUI::Card.new(bordered: true) do
        render PhlexyUI::CardTitle.new { "About #{@user.name}" }
        render PhlexyUI::CardBody.new do
          p(class: "text-base-content/70") { @user.bio }
          div(class: "mt-4 space-y-2") do
            render_fact("Email", @user.email)
            render_fact("Joined", @user.created_at.to_fs(:long))
            render_fact("Last seen", @user.last_seen_at.to_fs(:long)) if @user.last_seen_at
          end
        end
        render PhlexyUI::CardActions.new(justify: :end) do
          render PhlexyUI::Button.new(as: :a, variant: :primary, href: edit_profile_path) { "Edit profile" }
        end
      end
    end

    private

    def render_fact(label, value)
      div(class: "flex items-center gap-2 text-sm") do
        span(class: "font-semibold w-24") { label }
        span(class: "text-base-content/80") { value }
      end
    end
  end
end
