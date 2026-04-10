# shadcn_phlexcomponents composition patterns

This file is reference material for `/phlexed-build` and `/phlexed-component`. It
shows how to compose `shadcn_phlexcomponents` (the Phlex port of shadcn/ui) idiomatically.
When you generate Phlex views in a project that uses shadcn_phlexcomponents, your
output should look like the examples below.

**This file is not authoritative about which components exist.** That is what
`.phlexed/registry.json` is for. Always read the registry to confirm a component
is available before rendering it. Use this file to learn *how* to use what the
registry says *is* available.

**shadcn vs PhlexyUI:** shadcn_phlexcomponents is Tailwind-native (not DaisyUI-based).
Variants use semantic Tailwind color tokens (`bg-primary`, `text-destructive-foreground`)
backed by CSS variables defined in `app/assets/tailwind/application.css`. Interactive
components (Dialog, DropdownMenu, Select) wire up Stimulus controllers automatically
via `data-controller` attributes.

## Core conventions

### Full namespace, always

All components live under `ShadcnPhlexcomponents::`:

```ruby
# Correct
render ShadcnPhlexcomponents::Button.new(variant: :default) { "Save" }

# Wrong — never drop the namespace
render Button.new(variant: :default) { "Save" }
```

Projects often alias the namespace to make composition less noisy:

```ruby
# config/initializers/shadcn.rb
Shadcn = ShadcnPhlexcomponents

# Then in views
render Shadcn::Button.new(variant: :default) { "Save" }
```

Both forms are acceptable. Match whatever the project already uses (grep existing
views for `Shadcn::` vs `ShadcnPhlexcomponents::`).

### Props, not CSS classes

shadcn components map props to pre-built Tailwind class vocabularies. Writing the
classes yourself bypasses the component's styling contract and breaks with future
upgrades:

```ruby
# Correct
render Shadcn::Button.new(variant: :destructive, size: :sm) { "Delete" }

# Wrong — hardcoded classes defeat the library
button(class: "inline-flex items-center bg-destructive text-destructive-foreground h-9 rounded-md px-3") { "Delete" }
```

### Semantic Tailwind colors, not literal ones

shadcn's theme defines CSS variables: `--primary`, `--destructive`, `--muted`, etc.
Tailwind classes like `bg-primary`, `text-muted-foreground` resolve against them.
Use these, never literal color utilities:

```ruby
# Correct — respects light/dark mode and theme overrides
div(class: "bg-muted text-muted-foreground rounded-md p-4") { "Subtle content" }

# Wrong — will look broken under dark mode
div(class: "bg-gray-100 text-gray-600 rounded-md p-4") { "Subtle content" }
```

### Two subcomponent patterns: siblings and factories

shadcn components use one of two patterns for composition. You must match the
pattern the parent component defines.

**Pattern A: sibling classes** (Card, Table, Avatar). Child components are separate
classes and you render them as siblings:

```ruby
render Shadcn::Card.new do
  render Shadcn::CardHeader.new do
    render Shadcn::CardTitle.new { "Account" }
    render Shadcn::CardDescription.new { "Manage your profile and preferences" }
  end
  render Shadcn::CardContent.new do
    para { "Body content here" }
  end
  render Shadcn::CardFooter.new do
    render Shadcn::Button.new(variant: :default) { "Save" }
  end
end
```

**Pattern B: factory methods** (Dialog, DropdownMenu, Select, Accordion, Tabs).
The parent yields its own instance and you call factory methods on it:

```ruby
render Shadcn::Dialog.new do |dialog|
  dialog.trigger(variant: :outline) { "Open dialog" }
  dialog.content do
    dialog.header do
      dialog.title { "Are you sure?" }
      dialog.description { "This action cannot be undone." }
    end
    dialog.footer do
      render Shadcn::Button.new(variant: :ghost) { "Cancel" }
      render Shadcn::Button.new(variant: :destructive) { "Delete" }
    end
  end
end
```

**Which components use which pattern?** Check the registry — each component entry
lists `subcomponents` (factory method names) and `slots` (phlex slot names). If
`subcomponents` is non-empty, use Pattern B. If the registry has sibling classes
like `CardHeader` alongside `Card`, use Pattern A.

**Never mix patterns.** A `Card` does not have a `.header` factory method; a
`Dialog` does not have a `DialogHeader` sibling class. Match the exemplar.

## Layout

shadcn doesn't ship layout primitives (no `Container`, `Stack`, `Grid`). Use
Tailwind utility classes directly for layout geometry. This is expected and
idiomatic for shadcn:

```ruby
class DashboardView < Views::Base
  def view_template
    div(class: "container mx-auto p-6 space-y-6") do
      h1(class: "text-3xl font-bold tracking-tight") { "Dashboard" }

      div(class: "grid grid-cols-1 md:grid-cols-3 gap-4") do
        render Shadcn::Card.new do
          render Shadcn::CardHeader.new do
            render Shadcn::CardTitle.new { "Revenue" }
          end
          render Shadcn::CardContent.new { "$12,400" }
        end

        render Shadcn::Card.new do
          render Shadcn::CardHeader.new do
            render Shadcn::CardTitle.new { "Users" }
          end
          render Shadcn::CardContent.new { "1,204" }
        end

        render Shadcn::Card.new do
          render Shadcn::CardHeader.new do
            render Shadcn::CardTitle.new { "Conversion" }
          end
          render Shadcn::CardContent.new { "4.2%" }
        end
      end
    end
  end
end
```

Note: `container mx-auto p-6`, `grid grid-cols-*`, `space-y-*`, and `gap-*` are
acceptable Tailwind utilities. What you must not do is write color utilities
(`bg-blue-500`) or component utilities (reinventing a button with `inline-flex
items-center ...`). Layout geometry is fine; visual styling must go through
components.

### Separators and spacing

```ruby
render Shadcn::Separator.new
render Shadcn::Separator.new(orientation: :vertical)
```

## Forms

shadcn form components wire up labels, inputs, and validation errors. The
canonical pattern uses `FormField`:

```ruby
class SettingsProfileView < Views::Base
  def initialize(user:)
    @user = user
  end

  def view_template
    render Shadcn::Card.new do
      render Shadcn::CardHeader.new do
        render Shadcn::CardTitle.new { "Profile" }
        render Shadcn::CardDescription.new { "Update your public profile" }
      end
      render Shadcn::CardContent.new do
        form_with(model: @user, url: settings_profile_path, class: "space-y-4") do |f|
          render Shadcn::FormField.new(name: :name, label: "Name", error: @user.errors[:name].first) do
            plain f.text_field(:name, class: "flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm")
          end

          render Shadcn::FormField.new(name: :email, label: "Email", error: @user.errors[:email].first) do
            plain f.email_field(:email, class: "flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm")
          end

          render Shadcn::FormField.new(name: :bio, label: "Bio", hint: "Max 200 characters") do
            plain f.text_area(:bio, rows: 4, class: "flex min-h-[60px] w-full rounded-md border border-input bg-transparent px-3 py-2 text-sm")
          end

          div(class: "flex justify-end") do
            render Shadcn::Button.new(type: "submit", variant: :default) { "Save changes" }
          end
        end
      end
    end
  end
end
```

**When to use Shadcn::Input vs a raw Rails form field:** If the project has
`Shadcn::Input` in the registry, prefer it for pure Phlex forms. For Rails
`form_with` integration, use `f.text_field` + the shadcn input class string
inline. Rails generates the `<input>` element, so the component version would
double-render.

### Pure Phlex form (no Rails helpers)

```ruby
form(action: "/search", method: "get", class: "flex gap-2") do
  render Shadcn::Input.new(type: "search", name: "q", placeholder: "Search...")
  render Shadcn::Button.new(type: "submit", variant: :default) { "Go" }
end
```

### Select

```ruby
render Shadcn::Select.new(name: :country) do |select|
  select.trigger { select.value(placeholder: "Choose a country") }
  select.content do
    select.item(value: "us") { "United States" }
    select.item(value: "uk") { "United Kingdom" }
    select.item(value: "ca") { "Canada" }
  end
end
```

### Checkbox and radio

```ruby
# Checkbox (standalone)
render Shadcn::Checkbox.new(id: "terms", name: "accept_terms")
label(for: "terms", class: "text-sm ml-2") { "I agree to the terms" }

# Radio group
render Shadcn::RadioGroup.new(name: "plan", default_value: "pro") do |group|
  group.item(value: "hobby") { "Hobby" }
  group.item(value: "pro") { "Pro" }
  group.item(value: "team") { "Team" }
end
```

## Actions

### Buttons

shadcn button variants are `default`, `destructive`, `outline`, `secondary`,
`ghost`, `link`. Sizes are `default`, `sm`, `lg`, `icon`.

```ruby
# Primary action
render Shadcn::Button.new(variant: :default) { "Save" }

# Secondary / cancel
render Shadcn::Button.new(variant: :secondary) { "Cancel" }

# Ghost (minimal weight)
render Shadcn::Button.new(variant: :ghost) { "Close" }

# Destructive
render Shadcn::Button.new(variant: :destructive) { "Delete account" }

# Outlined
render Shadcn::Button.new(variant: :outline) { "Download" }

# Link-styled
render Shadcn::Button.new(variant: :link, as: :a, href: "/docs") { "Read docs" }

# Sized
render Shadcn::Button.new(variant: :default, size: :lg) { "Get started" }
render Shadcn::Button.new(variant: :ghost, size: :sm) { "More" }

# Icon-only button
render Shadcn::Button.new(variant: :outline, size: :icon) { "⚙" }

# Disabled
render Shadcn::Button.new(variant: :default, disabled: true) { "Saving..." }
```

**Do not invent new variants.** If you need something outside the registered
set, invoke `/phlexed-component` and extend the component formally. Do not
pass raw classes.

### Dialog (modal)

Dialog is the canonical factory-method example:

```ruby
render Shadcn::Dialog.new do |dialog|
  dialog.trigger(variant: :outline) { "Edit profile" }
  dialog.content do
    dialog.header do
      dialog.title { "Edit profile" }
      dialog.description { "Make changes to your profile here. Click save when done." }
    end

    div(class: "grid gap-4 py-4") do
      render Shadcn::FormField.new(name: :name, label: "Name") do
        render Shadcn::Input.new(value: @user.name)
      end
      render Shadcn::FormField.new(name: :email, label: "Email") do
        render Shadcn::Input.new(value: @user.email, type: "email")
      end
    end

    dialog.footer do
      render Shadcn::Button.new(type: "submit", variant: :default) { "Save changes" }
    end
  end
end
```

The Dialog handles open/close state via a Stimulus controller — you don't need
to write JavaScript. Trigger opens it; Escape or clicking the overlay closes it.

### Dropdown menu

```ruby
render Shadcn::DropdownMenu.new do |menu|
  menu.trigger(variant: :outline) { "Options ▾" }
  menu.content do
    menu.label { "Actions" }
    menu.separator
    menu.item { "Edit" }
    menu.item { "Duplicate" }
    menu.separator
    menu.item(variant: :destructive) { "Delete" }
  end
end
```

### Alert dialog (confirmation)

`AlertDialog` is the blocking confirmation variant of `Dialog` — use it for
destructive actions that need explicit confirmation:

```ruby
render Shadcn::AlertDialog.new do |alert|
  alert.trigger(variant: :destructive) { "Delete account" }
  alert.content do
    alert.header do
      alert.title { "Are you absolutely sure?" }
      alert.description { "This will permanently delete your account and all data." }
    end
    alert.footer do
      alert.cancel { "Cancel" }
      alert.action(variant: :destructive) { "Yes, delete" }
    end
  end
end
```

## Feedback

### Alert

```ruby
render Shadcn::Alert.new(variant: :default) do |alert|
  alert.title { "Heads up!" }
  alert.description { "Your changes have been saved." }
end

render Shadcn::Alert.new(variant: :destructive) do |alert|
  alert.title { "Error" }
  alert.description { "Could not process your payment." }
end
```

### Badge

```ruby
render Shadcn::Badge.new(variant: :default) { "New" }
render Shadcn::Badge.new(variant: :secondary) { "Draft" }
render Shadcn::Badge.new(variant: :destructive) { "Failed" }
render Shadcn::Badge.new(variant: :outline) { "Beta" }
```

### Toast (via Toaster)

shadcn toasts are triggered imperatively via a Stimulus controller. The template
mounts a single `Toaster` at the layout level:

```ruby
# app/views/layouts/application_layout.rb
class ApplicationLayout < Views::Base
  def view_template(&)
    doctype
    html do
      head do
        # ...
      end
      body do
        yield_content(&)
        render Shadcn::Toaster.new
      end
    end
  end
end
```

Then trigger a toast from a controller or Stimulus action using the library's
JS helper. Raw toast rendering inline is not the pattern — mount Toaster once
and call it.

### Skeleton (loading placeholder)

```ruby
div(class: "space-y-2") do
  render Shadcn::Skeleton.new(class: "h-4 w-[250px]")
  render Shadcn::Skeleton.new(class: "h-4 w-[200px]")
end
```

## Navigation

### Navigation menu

```ruby
render Shadcn::NavigationMenu.new do |nav|
  nav.list do
    nav.item do
      nav.link(href: "/products") { "Products" }
    end
    nav.item do
      nav.trigger { "Company" }
      nav.content do
        ul(class: "grid w-[400px] gap-3 p-4") do
          li { a(href: "/about") { "About" } }
          li { a(href: "/team") { "Team" } }
          li { a(href: "/careers") { "Careers" } }
        end
      end
    end
  end
end
```

### Tabs

```ruby
render Shadcn::Tabs.new(default_value: "profile") do |tabs|
  tabs.list do
    tabs.trigger(value: "profile") { "Profile" }
    tabs.trigger(value: "security") { "Security" }
    tabs.trigger(value: "notifications") { "Notifications" }
  end

  tabs.content(value: "profile") do
    render Shadcn::Card.new do
      render Shadcn::CardContent.new { "Profile settings here" }
    end
  end

  tabs.content(value: "security") do
    render Shadcn::Card.new do
      render Shadcn::CardContent.new { "Security settings here" }
    end
  end

  tabs.content(value: "notifications") do
    render Shadcn::Card.new do
      render Shadcn::CardContent.new { "Notification settings here" }
    end
  end
end
```

### Breadcrumb

```ruby
render Shadcn::Breadcrumb.new do |crumb|
  crumb.list do
    crumb.item { crumb.link(href: "/") { "Home" } }
    crumb.separator
    crumb.item { crumb.link(href: "/settings") { "Settings" } }
    crumb.separator
    crumb.item { crumb.page { "Profile" } }
  end
end
```

## Data display

### Table

```ruby
render Shadcn::Table.new do
  render Shadcn::TableHeader.new do
    render Shadcn::TableRow.new do
      render Shadcn::TableHead.new { "Name" }
      render Shadcn::TableHead.new { "Role" }
      render Shadcn::TableHead.new { "Status" }
      render Shadcn::TableHead.new(class: "text-right") { "" }
    end
  end
  render Shadcn::TableBody.new do
    @users.each do |user|
      render Shadcn::TableRow.new do
        render Shadcn::TableCell.new { user.name }
        render Shadcn::TableCell.new { user.role }
        render Shadcn::TableCell.new do
          variant = user.active? ? :default : :secondary
          render Shadcn::Badge.new(variant: variant) do
            user.active? ? "Active" : "Inactive"
          end
        end
        render Shadcn::TableCell.new(class: "text-right") do
          render Shadcn::Button.new(variant: :ghost, size: :sm, as: :a, href: user_path(user)) { "Edit" }
        end
      end
    end
  end
end
```

### Avatar

```ruby
render Shadcn::Avatar.new do |avatar|
  avatar.image(src: user.avatar_url, alt: user.name)
  avatar.fallback { user.initials }
end
```

### Accordion

```ruby
render Shadcn::Accordion.new(type: :single, collapsible: true) do |accordion|
  accordion.item(value: "item-1") do |item|
    item.trigger { "Is it accessible?" }
    item.content { "Yes. It adheres to the WAI-ARIA design pattern." }
  end

  accordion.item(value: "item-2") do |item|
    item.trigger { "Is it styled?" }
    item.content { "Yes. It comes with default styles that match the rest of shadcn." }
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
    div(class: "container mx-auto max-w-3xl p-6 space-y-6") do
      div do
        h1(class: "text-3xl font-bold tracking-tight") { "Settings" }
        para(class: "text-muted-foreground") { "Manage your account and preferences." }
      end

      render Shadcn::Tabs.new(default_value: "profile") do |tabs|
        tabs.list(class: "grid w-full grid-cols-3") do
          tabs.trigger(value: "profile") { "Profile" }
          tabs.trigger(value: "security") { "Security" }
          tabs.trigger(value: "danger") { "Danger zone" }
        end

        tabs.content(value: "profile") do
          render Shadcn::Card.new do
            render Shadcn::CardHeader.new do
              render Shadcn::CardTitle.new { "Profile" }
              render Shadcn::CardDescription.new { "Update your public profile information." }
            end
            render Shadcn::CardContent.new do
              form_with(model: @user, url: settings_profile_path, class: "space-y-4") do |f|
                render Shadcn::FormField.new(name: :name, label: "Name") do
                  plain f.text_field(:name, class: "flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm")
                end
                render Shadcn::FormField.new(name: :email, label: "Email") do
                  plain f.email_field(:email, class: "flex h-9 w-full rounded-md border border-input bg-transparent px-3 py-1 text-sm shadow-sm")
                end
              end
            end
            render Shadcn::CardFooter.new(class: "flex justify-end") do
              render Shadcn::Button.new(type: "submit", variant: :default) { "Save changes" }
            end
          end
        end

        tabs.content(value: "security") do
          render Shadcn::Card.new do
            render Shadcn::CardHeader.new do
              render Shadcn::CardTitle.new { "Security" }
              render Shadcn::CardDescription.new { "Change your password and manage sessions." }
            end
            render Shadcn::CardContent.new do
              para { "Password last changed 3 months ago." }
            end
            render Shadcn::CardFooter.new do
              render Shadcn::Button.new(variant: :outline, as: :a, href: "/settings/password") { "Change password" }
            end
          end
        end

        tabs.content(value: "danger") do
          render Shadcn::Card.new(class: "border-destructive") do
            render Shadcn::CardHeader.new do
              render Shadcn::CardTitle.new(class: "text-destructive") { "Danger zone" }
              render Shadcn::CardDescription.new { "Permanently delete your account and all data." }
            end
            render Shadcn::CardFooter.new do
              render Shadcn::AlertDialog.new do |alert|
                alert.trigger(variant: :destructive) { "Delete account" }
                alert.content do
                  alert.header do
                    alert.title { "Are you absolutely sure?" }
                    alert.description { "This cannot be undone. Your account and all associated data will be permanently removed." }
                  end
                  alert.footer do
                    alert.cancel { "Cancel" }
                    alert.action(variant: :destructive) { "Yes, delete my account" }
                  end
                end
              end
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
    { name: "Hobby", price: "$0",  features: ["1 project", "Community support"],         variant: :outline },
    { name: "Pro",   price: "$19", features: ["Unlimited projects", "Email support", "Custom domains"], variant: :default },
    { name: "Team",  price: "$49", features: ["Everything in Pro", "Team collaboration", "SSO"],         variant: :outline }
  ].freeze

  def view_template
    div(class: "container mx-auto py-16") do
      div(class: "text-center mb-12") do
        h1(class: "text-5xl font-bold tracking-tight") { "Pricing" }
        para(class: "text-muted-foreground mt-4 text-lg") { "Simple, transparent pricing. No hidden fees." }
      end

      div(class: "grid grid-cols-1 md:grid-cols-3 gap-6 max-w-5xl mx-auto") do
        PLANS.each do |plan|
          featured = plan[:name] == "Pro"
          render Shadcn::Card.new(class: featured ? "border-primary shadow-lg scale-105" : "") do
            render Shadcn::CardHeader.new do
              render Shadcn::CardTitle.new { plan[:name] }
              render Shadcn::CardDescription.new do
                span(class: "text-4xl font-bold text-foreground") { plan[:price] }
                span(class: "text-muted-foreground") { "/mo" }
              end
            end
            render Shadcn::CardContent.new do
              ul(class: "space-y-2") do
                plan[:features].each do |feature|
                  li(class: "flex items-center text-sm") { "✓ #{feature}" }
                end
              end
            end
            render Shadcn::CardFooter.new do
              render Shadcn::Button.new(variant: plan[:variant], class: "w-full", as: :a, href: "/signup?plan=#{plan[:name].downcase}") do
                "Get #{plan[:name]}"
              end
            end
          end
        end
      end
    end
  end
end
```

## Anti-patterns

### Inline Tailwind instead of components

```ruby
# BAD
button(class: "inline-flex items-center bg-primary text-primary-foreground h-9 rounded-md px-4") { "Save" }

# GOOD
render Shadcn::Button.new(variant: :default) { "Save" }
```

### Literal colors instead of semantic tokens

```ruby
# BAD — breaks under dark mode, breaks under theme overrides
div(class: "bg-gray-900 text-white")

# GOOD — respects theme
div(class: "bg-background text-foreground")

# Also good
div(class: "bg-muted text-muted-foreground")
```

### Inline `style=""` attributes

```ruby
# BAD
div(style: "padding: 16px; background: #f5f5f5")

# GOOD — use Card for the container pattern
render Shadcn::Card.new do
  render Shadcn::CardContent.new { "..." }
end
```

### Reinventing component internals

```ruby
# BAD — recreating what Card already does
div(class: "rounded-lg border bg-card text-card-foreground shadow-sm") do
  div(class: "flex flex-col space-y-1.5 p-6") do
    h3(class: "font-semibold leading-none tracking-tight") { "Title" }
  end
  div(class: "p-6 pt-0") { "Body" }
end

# GOOD
render Shadcn::Card.new do
  render Shadcn::CardHeader.new do
    render Shadcn::CardTitle.new { "Title" }
  end
  render Shadcn::CardContent.new { "Body" }
end
```

### Mixing subcomponent patterns

```ruby
# BAD — Dialog uses factory methods, not sibling classes
render Shadcn::Dialog.new do
  render Shadcn::DialogHeader.new { "..." }  # DialogHeader doesn't exist
  render Shadcn::DialogContent.new { "..." } # DialogContent doesn't exist
end

# GOOD
render Shadcn::Dialog.new do |dialog|
  dialog.header { "..." }
  dialog.content { "..." }
end
```

```ruby
# BAD — Card uses sibling classes, not factory methods
render Shadcn::Card.new do |card|
  card.header { "..." }  # card.header doesn't exist
  card.content { "..." } # card.content doesn't exist
end

# GOOD
render Shadcn::Card.new do
  render Shadcn::CardHeader.new { "..." }
  render Shadcn::CardContent.new { "..." }
end
```

When in doubt, check the registry: factory-method components have `subcomponents`
listed; sibling-class components have companion classes alongside the parent.

### Inventing variants

```ruby
# BAD — `primary` is not a valid shadcn Button variant
render Shadcn::Button.new(variant: :primary) { "Save" }

# GOOD — `default` is shadcn's primary-style variant
render Shadcn::Button.new(variant: :default) { "Save" }
```

shadcn uses `default | destructive | outline | secondary | ghost | link`.
PhlexyUI/DaisyUI uses `primary | secondary | accent | ghost | ...`. These are
**different vocabularies**. Do not mix them. Always check the registry for the
exact variant names.

### Writing JavaScript for interactive components

```ruby
# BAD — Dialog already has a Stimulus controller
render Shadcn::Dialog.new(id: "my-dialog") do
  # ... content
end
# plus custom JS to open/close
```

```ruby
# GOOD — trust the built-in Stimulus controller, use the factory pattern
render Shadcn::Dialog.new do |dialog|
  dialog.trigger(variant: :outline) { "Open" }
  dialog.content do
    # ... content
  end
end
```

If the built-in Stimulus controller doesn't handle your use case, file an issue
on shadcn_phlexcomponents — do not work around it with inline JS.

## When a pattern you need isn't here

This file covers the most common compositions. If you need something not shown:

1. Check `.phlexed/registry.json` for the component you want
2. Look at the component's source: `bundle show shadcn_phlexcomponents` →
   `lib/shadcn_phlexcomponents/components/<name>.rb`
3. If the pattern still doesn't exist in the registry, invoke `/phlexed-component`
   to create it instead of inlining raw markup

The anti-pattern you must never fall into is: "I'll just write this bit as raw
Tailwind because I don't see it in the registry." That's exactly how AI output
becomes inconsistent. Add the component to the registry first, then use it.
Layout geometry (grid, flex, spacing) via Tailwind utilities is acceptable;
visual styling must go through components.
