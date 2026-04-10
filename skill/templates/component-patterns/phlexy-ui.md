# PhlexyUI composition patterns

This file is reference material for `/phlexed-build` and `/phlexed-component`. It
shows how to compose PhlexyUI components idiomatically — with the correct namespaces,
props, and patterns. When you generate Phlex views in a PhlexyUI project, your
output should look like the examples below.

**This file is not authoritative about which components exist.** That is what
`.phlexed/registry.json` is for. Always read the registry to confirm a component
is available before rendering it. Use this file to learn *how* to use what the
registry says *is* available.

## Core conventions

### Full namespace, always

PhlexyUI components live under the `PhlexyUI::` namespace. Use the full class name
in every `render` call, even when you're writing code inside a class that already
references PhlexyUI:

```ruby
# Correct
render PhlexyUI::Button.new(variant: :primary) { "Save" }

# Wrong — never drop the namespace
render Button.new(variant: :primary) { "Save" }
```

### Props, not CSS classes

PhlexyUI maps props to DaisyUI classes under the hood. You write props; the
component writes the classes. Bypassing the prop DSL breaks theme switching and
makes retrofits painful.

```ruby
# Correct
render PhlexyUI::Button.new(variant: :primary, size: :lg) { "Continue" }

# Wrong — hardcoded classes defeat the library
div(class: "btn btn-primary btn-lg") { "Continue" }
```

### Blocks for children

Container components yield to blocks. Pass content as a block, not as a string prop:

```ruby
# Correct
render PhlexyUI::Card.new do
  render PhlexyUI::CardTitle.new { "Welcome" }
  render PhlexyUI::CardBody.new { "Sign in to continue." }
end

# Wrong — no prop called `content`
render PhlexyUI::Card.new(content: "Welcome...")
```

### Polymorphic element tag

Most PhlexyUI components accept an `as:` kwarg to change the rendered element.
Defaults are sensible (`Card` → `div`, `Button` → `button`). Override when
semantics demand it:

```ruby
# Render a link that looks like a button
render PhlexyUI::Button.new(as: :a, variant: :primary, href: "/signup") { "Sign up" }
```

## Layout

### Container → Card → CardBody

The standard page container pattern:

```ruby
class DashboardView < Views::Base
  def view_template
    render PhlexyUI::Container.new do
      render PhlexyUI::PageHeader.new do
        h1 { "Dashboard" }
      end

      render PhlexyUI::Card.new(bordered: true) do
        render PhlexyUI::CardBody.new do
          para { "Welcome back!" }
        end
      end
    end
  end
end
```

### Stack for vertical rhythm

`Stack` applies consistent spacing between direct children. Prefer it over manual
`mt-4` sprinkles:

```ruby
render PhlexyUI::Stack.new(gap: 4) do
  render PhlexyUI::Card.new { render PhlexyUI::CardBody.new { "First" } }
  render PhlexyUI::Card.new { render PhlexyUI::CardBody.new { "Second" } }
  render PhlexyUI::Card.new { render PhlexyUI::CardBody.new { "Third" } }
end
```

### Grid for 2+ column layouts

For dashboard-style layouts with multiple columns:

```ruby
div(class: "grid grid-cols-1 md:grid-cols-3 gap-4") do
  3.times do |i|
    render PhlexyUI::Stat.new do
      render PhlexyUI::StatTitle.new { "Metric #{i + 1}" }
      render PhlexyUI::StatValue.new { "#{100 + i * 50}" }
    end
  end
end
```

Note: Tailwind grid utilities are acceptable for layout geometry (rows/cols/gap).
What you must not do is bypass PhlexyUI components for *content* with raw classes.

## Forms

PhlexyUI form components pair with Rails' `form_with`. The pattern is:

1. `form_with` provides the form builder
2. Each field is a PhlexyUI input component (wrapped in a `FormControl` for label+hint)
3. Submit button is a PhlexyUI `Button`

```ruby
class SettingsProfileView < Views::Base
  def initialize(user:)
    @user = user
  end

  def view_template
    render PhlexyUI::Card.new(bordered: true) do
      render PhlexyUI::CardTitle.new { "Profile" }
      render PhlexyUI::CardBody.new do
        form_with(model: @user, url: settings_profile_path) do |f|
          render PhlexyUI::Stack.new(gap: 4) do
            render PhlexyUI::FormControl.new do
              plain f.label(:name, class: "label")
              plain f.text_field(:name, class: "input input-bordered")
            end

            render PhlexyUI::FormControl.new do
              plain f.label(:email, class: "label")
              plain f.email_field(:email, class: "input input-bordered")
            end

            render PhlexyUI::FormControl.new do
              plain f.label(:notifications, class: "label cursor-pointer")
              plain f.check_box(:notifications, class: "toggle toggle-primary")
            end

            render PhlexyUI::CardActions.new do
              render PhlexyUI::Button.new(type: "submit", variant: :primary) { "Save changes" }
            end
          end
        end
      end
    end
  end
end
```

Notes:
- `plain` emits the Rails form builder's HTML directly (Phlex doesn't escape it).
- Pair Rails form helpers with DaisyUI classes on `input input-bordered`,
  `toggle toggle-primary`, etc. This is the one place where raw class names are
  acceptable because Rails generates the `<input>` element, not PhlexyUI.
- Wrap everything in `PhlexyUI::FormControl` for consistent label/hint spacing.

### Pure Phlex form (no Rails helpers)

When you don't need Rails' CSRF/form-object machinery, use plain Phlex + PhlexyUI:

```ruby
render PhlexyUI::FormControl.new do
  label(class: "label") { span(class: "label-text") { "Search" } }
  render PhlexyUI::Input.new(type: "search", placeholder: "Type to search…")
end
```

## Actions

### Buttons

```ruby
# Primary action
render PhlexyUI::Button.new(variant: :primary) { "Save" }

# Secondary / cancel
render PhlexyUI::Button.new(variant: :ghost) { "Cancel" }

# Destructive
render PhlexyUI::Button.new(variant: :error) { "Delete" }

# Outlined
render PhlexyUI::Button.new(variant: :outline) { "Download" }

# Sized
render PhlexyUI::Button.new(variant: :primary, size: :lg) { "Get started" }
render PhlexyUI::Button.new(variant: :ghost,   size: :xs) { "More" }

# Disabled / loading
render PhlexyUI::Button.new(variant: :primary, disabled: true) { "Saving…" }
```

### Button groups (CardActions)

When multiple buttons appear together, wrap them in `CardActions` for consistent
spacing and alignment:

```ruby
render PhlexyUI::CardActions.new(justify: :end) do
  render PhlexyUI::Button.new(variant: :ghost)   { "Cancel" }
  render PhlexyUI::Button.new(variant: :primary) { "Save" }
end
```

### Dropdowns

```ruby
render PhlexyUI::Dropdown.new do
  render PhlexyUI::Button.new(variant: :ghost) { "Options ▾" }
  render PhlexyUI::DropdownContent.new do
    ul(class: "menu") do
      li { a(href: "/edit") { "Edit" } }
      li { a(href: "/duplicate") { "Duplicate" } }
      li { a(href: "/delete", class: "text-error") { "Delete" } }
    end
  end
end
```

### Modals

```ruby
render PhlexyUI::Modal.new(id: "confirm-delete") do
  render PhlexyUI::ModalBox.new do
    h3 { "Are you sure?" }
    para { "This action cannot be undone." }
    render PhlexyUI::ModalActions.new do
      render PhlexyUI::Button.new(variant: :ghost)  { "Cancel" }
      render PhlexyUI::Button.new(variant: :error)  { "Delete" }
    end
  end
end
```

## Feedback

### Alerts

```ruby
render PhlexyUI::Alert.new(variant: :info) do
  "Your changes have been saved."
end

render PhlexyUI::Alert.new(variant: :warning) do
  "This domain expires in 7 days."
end

render PhlexyUI::Alert.new(variant: :error) do
  "Could not process payment."
end
```

### Badges

```ruby
render PhlexyUI::Badge.new(variant: :success, size: :sm) { "Active" }
render PhlexyUI::Badge.new(variant: :neutral, size: :sm) { "Draft" }
render PhlexyUI::Badge.new(variant: :warning, size: :sm) { "Pending" }
```

### Loading states

```ruby
# Spinner
render PhlexyUI::Loading.new(variant: :spinner, size: :lg)

# Dots
render PhlexyUI::Loading.new(variant: :dots, size: :md)

# In a button
render PhlexyUI::Button.new(variant: :primary, disabled: true) do
  render PhlexyUI::Loading.new(variant: :spinner, size: :sm)
  plain " Saving…"
end
```

### Toasts

Toasts are usually container-positioned; use `Toast` to wrap one or more `Alert`s:

```ruby
render PhlexyUI::Toast.new(position: [:top, :end]) do
  render PhlexyUI::Alert.new(variant: :success) { "Saved!" }
end
```

## Navigation

### Navbar

```ruby
render PhlexyUI::Navbar.new(bordered: true) do
  div(class: "flex-1") do
    a(href: "/", class: "btn btn-ghost text-xl") { "Acme" }
  end
  div(class: "flex-none") do
    ul(class: "menu menu-horizontal px-1") do
      li { a(href: "/pricing") { "Pricing" } }
      li { a(href: "/docs")    { "Docs" } }
      li do
        render PhlexyUI::Button.new(as: :a, variant: :primary, href: "/signup") { "Sign up" }
      end
    end
  end
end
```

### Tabs

```ruby
render PhlexyUI::Tabs.new(variant: :boxed) do
  render PhlexyUI::Tab.new(active: true) { "Profile" }
  render PhlexyUI::Tab.new              { "Security" }
  render PhlexyUI::Tab.new              { "Notifications" }
end
```

### Breadcrumbs

```ruby
render PhlexyUI::Breadcrumbs.new do
  ul do
    li { a(href: "/") { "Home" } }
    li { a(href: "/settings") { "Settings" } }
    li { "Profile" }
  end
end
```

## Data display

### Stats

```ruby
div(class: "stats shadow") do
  render PhlexyUI::Stat.new do
    render PhlexyUI::StatTitle.new { "Total users" }
    render PhlexyUI::StatValue.new { "31,400" }
    render PhlexyUI::StatDesc.new  { "↗︎ 400 (22%)" }
  end

  render PhlexyUI::Stat.new do
    render PhlexyUI::StatTitle.new { "Revenue" }
    render PhlexyUI::StatValue.new { "$12.4k" }
    render PhlexyUI::StatDesc.new(variant: :success) { "↗︎ 8% MoM" }
  end
end
```

### Tables

```ruby
render PhlexyUI::Table.new(zebra: true) do
  thead do
    tr do
      th { "Name" }
      th { "Role" }
      th { "Status" }
      th { "" }
    end
  end
  tbody do
    @users.each do |user|
      tr do
        td { user.name }
        td { user.role }
        td do
          status_variant = user.active? ? :success : :neutral
          render PhlexyUI::Badge.new(variant: status_variant, size: :sm) do
            user.active? ? "Active" : "Inactive"
          end
        end
        td do
          render PhlexyUI::Button.new(as: :a, variant: :ghost, size: :xs, href: user_path(user)) { "Edit" }
        end
      end
    end
  end
end
```

## Full page examples

### Settings page

```ruby
class SettingsIndexView < Views::Base
  def initialize(user:)
    @user = user
  end

  def view_template
    render PhlexyUI::Container.new do
      render PhlexyUI::Stack.new(gap: 6) do
        render PhlexyUI::PageHeader.new do
          h1 { "Settings" }
          para(class: "text-base-content/70") { "Manage your account and preferences." }
        end

        render PhlexyUI::Card.new(bordered: true) do
          render PhlexyUI::CardTitle.new { "Profile" }
          render PhlexyUI::CardBody.new do
            form_with(model: @user, url: settings_profile_path) do |f|
              render PhlexyUI::Stack.new(gap: 4) do
                render PhlexyUI::FormControl.new do
                  plain f.label(:name, class: "label")
                  plain f.text_field(:name, class: "input input-bordered")
                end

                render PhlexyUI::FormControl.new do
                  plain f.label(:email, class: "label")
                  plain f.email_field(:email, class: "input input-bordered")
                end

                render PhlexyUI::CardActions.new(justify: :end) do
                  render PhlexyUI::Button.new(type: "submit", variant: :primary) { "Save" }
                end
              end
            end
          end
        end

        render PhlexyUI::Card.new(bordered: true) do
          render PhlexyUI::CardTitle.new { "Security" }
          render PhlexyUI::CardBody.new do
            para { "Password last changed 3 months ago." }
            render PhlexyUI::CardActions.new(justify: :end) do
              render PhlexyUI::Button.new(as: :a, variant: :outline, href: "/settings/password") { "Change password" }
            end
          end
        end

        render PhlexyUI::Card.new(bordered: true) do
          render PhlexyUI::CardTitle.new(variant: :error) { "Danger zone" }
          render PhlexyUI::CardBody.new do
            para { "Permanently delete your account and all associated data." }
            render PhlexyUI::CardActions.new(justify: :end) do
              render PhlexyUI::Button.new(variant: :error, "data-modal": "delete-account") { "Delete account" }
            end
          end
        end
      end
    end
  end
end
```

### Pricing page

```ruby
class PricingIndexView < Views::Base
  PLANS = [
    { name: "Hobby",  price: "$0",   features: ["1 project", "Community support"] },
    { name: "Pro",    price: "$19",  features: ["Unlimited projects", "Email support", "Custom domains"] },
    { name: "Team",   price: "$49",  features: ["Everything in Pro", "Team collaboration", "SSO"] }
  ].freeze

  def view_template
    render PhlexyUI::Hero.new do
      div(class: "text-center") do
        h1(class: "text-5xl font-bold") { "Pricing" }
        para(class: "py-6") { "Simple, transparent pricing. No hidden fees." }
      end
    end

    render PhlexyUI::Container.new do
      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6") do
        PLANS.each do |plan|
          render PhlexyUI::Card.new(bordered: true) do
            render PhlexyUI::CardTitle.new { plan[:name] }
            render PhlexyUI::CardBody.new do
              div(class: "text-4xl font-bold") { "#{plan[:price]}/mo" }
              ul(class: "mt-4 space-y-2") do
                plan[:features].each do |feature|
                  li { "✓ #{feature}" }
                end
              end
            end
            render PhlexyUI::CardActions.new(justify: :end) do
              render PhlexyUI::Button.new(as: :a, variant: :primary, href: "/signup?plan=#{plan[:name].downcase}") { "Get #{plan[:name]}" }
            end
          end
        end
      end
    end
  end
end
```

## Anti-patterns

These are the most common failure modes when Claude generates PhlexyUI code
without this template. Each bad example has its correct replacement.

### Inline Tailwind instead of components

```ruby
# BAD
button(class: "bg-blue-500 hover:bg-blue-600 text-white font-bold py-2 px-4 rounded") { "Save" }

# GOOD
render PhlexyUI::Button.new(variant: :primary) { "Save" }
```

### Hardcoded colors instead of semantic names

```ruby
# BAD
div(class: "bg-gray-800 text-gray-100")

# GOOD — respects theme switching
div(class: "bg-neutral text-neutral-content")
```

### Inline `style=""` attributes

```ruby
# BAD
div(style: "padding: 16px; background: #f5f5f5")

# GOOD
render PhlexyUI::Card.new do
  render PhlexyUI::CardBody.new { ... }
end
```

### Reinventing card layouts

```ruby
# BAD
div(class: "border rounded-lg shadow-sm p-6") do
  h2(class: "text-lg font-semibold mb-2") { "Title" }
  para { "Body text" }
end

# GOOD
render PhlexyUI::Card.new(bordered: true) do
  render PhlexyUI::CardTitle.new { "Title" }
  render PhlexyUI::CardBody.new  { "Body text" }
end
```

### Dropping the namespace

```ruby
# BAD — will fail with NameError: uninitialized constant Button
render Button.new(variant: :primary) { "Save" }

# GOOD
render PhlexyUI::Button.new(variant: :primary) { "Save" }
```

### Guessing prop names

```ruby
# BAD — `type` is an HTML attribute, not a variant prop
render PhlexyUI::Button.new(type: :primary) { "Save" }

# GOOD — `variant:` is the prop for visual style, `type:` is the HTML attribute
render PhlexyUI::Button.new(variant: :primary, type: "submit") { "Save" }
```

### Custom CSS files for styling

```ruby
# BAD — creates a new file like app/assets/stylesheets/custom.css
# with .my-button { ... }

# GOOD — extend the theme in tailwind.config.js or use existing DaisyUI classes.
# New colors go in the theme config, not in a stylesheet.
```

## When a pattern you need isn't here

This file covers the most common compositions. If you need something not shown:

1. Check `.phlexed/registry.json` for the component you want
2. Look at a sibling component's source: `bundle show phlexy_ui` → `lib/phlexy_ui/<similar>.rb`
3. If the pattern still doesn't exist in the registry, invoke `/phlexed-component`
   to create it instead of inlining raw markup

The anti-pattern you must never fall into is: "I'll just write this bit as raw
Tailwind because I don't see it in the registry." That's exactly how AI output
becomes inconsistent. Add the component to the registry first, then use it.
