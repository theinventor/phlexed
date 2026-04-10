# phlexed

AI skill system for Phlex UI development in Rails. Makes Claude Code produce consistent, component-based Phlex output every time.

## What it does

Drop phlexed into a Rails project and Claude Code instantly knows your component library, your styling patterns, and your conventions. Every prompt produces well-composed Phlex components instead of inline Tailwind spaghetti.

Works with existing Phlex component libraries:
- [PhlexyUI](https://phlexyui.com/)
- [shadcn_phlexcomponents](https://github.com/sean-yeoh/shadcn_phlexcomponents)
- Your own custom Phlex components

## Install

```bash
git clone git@github.com:theinventor/phlexed.git ~/.claude/skills/phlexed
cd ~/.claude/skills/phlexed
./setup
```

Then in any Rails project with Phlex:

```
/phlexed-setup
```

## How it works

1. **Detects** your installed Phlex component library
2. **Builds a registry** of every available component (props, variants, examples)
3. **Configures Claude** with routing rules and prompt patterns
4. **Every prompt** now produces correct, component-based Phlex output

## Skills

- `/phlexed-setup` — Detect your component library, build registry, configure Claude
- `/phlexed-build` — Generate a page or feature using your registered components
- `/phlexed-component` — Create a new component following your library's patterns

## License

MIT
