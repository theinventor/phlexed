# Styling rules (phlexed)

This file is the authoritative rulebook for styling decisions across all phlexed
skills. `/phlexed-build`, `/phlexed-component`, `/phlexed-retrofit`, and `/phlexed-theme`
all consult it when generating or modifying view code. The concise summary that
gets appended to CLAUDE.md during `/phlexed-setup` is derived from this file — this
is the long-form version with concrete examples and the reasoning behind each rule.

**This file is not authoritative about which design system you use.** That comes
from `.phlexed/style-registry.json`. This file encodes the rules that apply
regardless of whether the project uses DaisyUI, raw Tailwind, or another system.

## The one-sentence rule

Every visual decision goes through a component, a prop, a theme token, or a
Tailwind utility — in that order. Anything else is a code smell.

## Decision ladder

When you need to style something, walk down this ladder and use the first option
that works:

1. **Is there a registered component that already renders this?** Use it.
   `render PhlexyUI::Button.new(variant: :primary)` beats `button(class: "btn btn-primary")`.
2. **Does the component accept a prop that would produce this look?** Set it.
   `render PhlexyUI::Card.new(bordered: true)` beats editing the class string.
3. **Is there a semantic theme token (DaisyUI class or Tailwind theme color)?** Use it.
   `bg-primary` beats `bg-blue-500`.
4. **Is there a Tailwind utility that expresses the geometry/spacing/typography?** Use it.
   `grid grid-cols-3 gap-4` for layout is fine.
5. **Does the design system need to be extended?** Extend it — in `tailwind.config.js`,
   not in a new CSS file.
6. **Do you need a new component variant?** Create it via `/phlexed-component`, not
   an ad-hoc class string.

Never skip ahead on the ladder. If step 1 gives you what you need, don't reach for
step 4.

## The 9 hard rules

### 1. Never inline `style=""` attributes

Every inline style is a hardcoded decision that breaks under theme switching and
resists refactoring.

```ruby
# BAD
div(style: "padding: 16px; background: #f5f5f5") { "..." }

# GOOD
render PhlexyUI::Card.new do
  render PhlexyUI::CardBody.new { "..." }
end
```

If you need one-off positioning (e.g., absolute positioning for an overlay),
use Tailwind utilities: `absolute top-4 right-4`. If even that isn't expressive
enough, the correct path is to extend `tailwind.config.js` with a custom utility,
not to inline style attributes.

### 2. Never hardcode colors

```ruby
# BAD
div(class: "bg-gray-800 text-gray-100") { "..." }
div(style: "color: #1F2937") { "..." }

# GOOD (DaisyUI)
div(class: "bg-neutral text-neutral-content") { "..." }

# GOOD (raw Tailwind with theme colors)
div(class: "bg-slate-800 text-slate-100") { "..." }  # OK if slate is in your theme
div(class: "bg-brand text-brand-content") { "..." }   # better — uses extended palette
```

**Why it matters:** hardcoded colors break theme switching, dark mode, and any
future rebrand. Semantic tokens (`bg-primary`, `text-muted-foreground`) resolve
to CSS variables that change per theme.

### 3. Never use raw color utilities when a semantic token exists

```ruby
# BAD — hardcoded red
render PhlexyUI::Badge.new(class: "bg-red-500 text-white") { "Error" }

# GOOD — semantic
render PhlexyUI::Badge.new(variant: :error) { "Error" }
```

DaisyUI has `btn-primary`, `btn-secondary`, `btn-accent`, `btn-success`, etc.
Raw `bg-blue-500` bypasses the semantic layer. Even for tones that seem fixed
("red = error"), use the semantic class so the theme can override it.

### 4. Never recreate components with utility classes

```ruby
# BAD — reinventing Card
div(class: "rounded-lg border border-gray-200 bg-white p-6 shadow-sm") do
  h3(class: "text-lg font-semibold") { "Title" }
  para(class: "mt-2 text-sm text-gray-600") { "Body" }
end

# GOOD
render PhlexyUI::Card.new(bordered: true) do
  render PhlexyUI::CardTitle.new { "Title" }
  render PhlexyUI::CardBody.new { "Body" }
end
```

If you find yourself composing the same utility combination twice, either (a)
check if a registered component already exists for it, or (b) create one via
`/phlexed-component`.

### 5. Never drop the component namespace

```ruby
# BAD — will fail with NameError in Rails
render Button.new(variant: :primary) { "Save" }

# GOOD
render PhlexyUI::Button.new(variant: :primary) { "Save" }
```

Always use the full class name from `.phlexed/registry.json`. This applies
uniformly — inside module-nested classes, inside ApplicationView, inside Phlex
base classes — every `render` gets the full namespace.

### 6. Never guess prop names

```ruby
# BAD — `type` is the HTML attribute, not the visual variant
render PhlexyUI::Button.new(type: :primary) { "Save" }

# GOOD
render PhlexyUI::Button.new(variant: :primary, type: "submit") { "Save" }
```

The registry lists the exact prop names for each component. If your guess isn't
in the registry, check the gem source at `$(bundle show phlexy_ui)/lib/phlexy_ui/<component>.rb`
before inventing one.

Different libraries use different prop vocabularies:
- PhlexyUI: `variant: :primary` (from DaisyUI's `btn-primary`)
- shadcn_phlexcomponents: `variant: :default` (from shadcn's `default` variant)

Do not cross-contaminate the vocabulary.

### 7. Never create custom CSS files when the design system can handle it

```ruby
# BAD — scattered styling sources
# app/assets/stylesheets/custom.css
# .my-button { background: #FF6600; padding: 8px 16px; }

# GOOD (option A): extend tailwind.config.js
# tailwind.config.js
# theme: { extend: { colors: { brand: "#FF6600" } } }
# Then in Ruby: render PhlexyUI::Button.new(class: "bg-brand") { "..." }

# GOOD (option B): create a proper Phlex component
# app/components/brand_button.rb
# class BrandButton < PhlexyUI::Base
#   register_modifiers(primary: "bg-brand text-white")
# end
```

The rule: all visual decisions live in one place — tailwind.config.js + Phlex
components. Scattered CSS files rot and confuse Claude when it reads the project
looking for styling patterns.

### 8. Never use raw `hover:` / `focus:` / `active:` on color utilities

```ruby
# BAD — manual hover on a hardcoded color
button(class: "bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded") { "Save" }

# GOOD — component's built-in hover states
render PhlexyUI::Button.new(variant: :primary) { "Save" }
```

Component libraries ship with proper hover/focus/active states already mapped
to the theme. Manually reinventing them is extra work AND breaks theme switching.

### 9. Data-theme lives on `<html>`, not individual elements

```ruby
# BAD — section-scoped theming
div(data: { theme: "dark" }, class: "p-6") do
  # ... some "dark mode" section
end

# GOOD — theme applies app-wide via layout
# app/views/layouts/application.html.erb
# <html data-theme="dark">
```

Section-scoped theming is an anti-pattern because it breaks accessibility
(users expect consistent appearance) and creates CSS variable cascading bugs.
If you need a "dark section on a light page," use DaisyUI's built-in theme
variants (`bg-neutral text-neutral-content`) which work without switching themes.

## Common scenarios and their correct answers

### "The user wants a custom color"

1. Add it to `tailwind.config.js` under `theme.extend.colors`:
   ```js
   theme: { extend: { colors: { brand: "#FF6600" } } }
   ```
2. Use it like any other Tailwind color: `bg-brand`, `text-brand`.
3. If the user wants theme-aware dark/light variants, add it to a DaisyUI
   custom theme via `/phlexed-theme custom`.

### "The user wants a new button variant"

1. Create a new component via `/phlexed-component`:
   ```ruby
   class PulseButton < PhlexyUI::Base
     def initialize(**)
       super(**)
     end

     def view_template(&)
       # ...
     end

     private
     register_modifiers(pulse: "animate-pulse")
   end
   ```
2. Or, if the variant is just a combination of existing modifiers, document it
   as a composition pattern in the project's CLAUDE.md rather than creating a
   new component.

### "The user wants to add a drop shadow"

1. First check if the component already has a shadow (Card does by default).
2. If not, use Tailwind's shadow utilities: `shadow`, `shadow-md`, `shadow-lg`.
3. If you need a specific custom shadow (unusual), extend `theme.extend.boxShadow`
   in `tailwind.config.js`.
4. Never inline `box-shadow: ...` via style attribute.

### "The user wants a gradient background"

1. Use Tailwind's gradient utilities: `bg-gradient-to-r from-primary to-secondary`.
2. Reference theme colors, not hardcoded hex values.
3. If you need a specific gradient across the whole app, create a component
   that encapsulates it (`HeroGradient`, `CardGradient`).

### "The user wants a one-off positioning fix"

1. Use Tailwind positioning utilities: `absolute top-4 right-4`, `fixed bottom-0`.
2. Use Tailwind spacing utilities for the offsets: `p-4`, `m-2`, `space-x-4`.
3. Never inline style attributes.

### "The user wants responsive behavior"

1. Use Tailwind breakpoint prefixes: `sm:`, `md:`, `lg:`, `xl:`, `2xl:`.
2. Never write custom media queries.
3. For truly complex responsive logic (e.g., container queries), use Tailwind
   plugins or extend `theme.extend.screens`.

## When a rule seems to get in the way

The rules above cover 95% of styling decisions. The remaining 5% are edge cases
where you might think "this rule doesn't fit my situation." Before breaking the
rule:

1. **Check `.phlexed/style-registry.json`** — the design system may already
   handle your case with a modifier you hadn't seen.
2. **Check an existing exemplar** — find a similar pattern elsewhere in the
   project and see how it was solved.
3. **Ask via AskUserQuestion** — present the user with the anti-pattern and the
   correct alternatives. Let them choose.
4. **Extend the theme config** — adding a color, utility, or shadow to
   `tailwind.config.js` is almost always the correct escape hatch. It keeps the
   styling vocabulary centralized.

Only after all four fail should you consider a rule exception — and document
it inline with a comment explaining why: `# phlexed:allow inline-style — required
for <specific browser quirk>`.

## How this file is used

- **`/phlexed-build`** reads this file before generating view classes. Every
  component render and class string is checked against these rules.
- **`/phlexed-component`** reads this file when creating new components to
  ensure their internal styling follows the design system.
- **`/phlexed-retrofit`** injects the decision ladder into the generated
  PROMPT.md so Ralph follows the same rules during conversions.
- **`/phlexed-theme`** audit mode scans for violations of these 9 rules and
  reports them.
- **`/phlexed-setup`** appends a condensed version of these rules to CLAUDE.md
  so Claude Code sees them on every interaction in the project.

If you find yourself writing code that fights these rules, the rules aren't
wrong — you're usually either missing a registered component (create one) or
missing a theme extension (add it). The styling system is already expressive
enough for 99% of real Rails UI; the remaining 1% usually means the project
needs a small design system extension, not a rule break.
