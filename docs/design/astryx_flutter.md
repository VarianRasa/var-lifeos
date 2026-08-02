# Astryx design system for Var

This document is Var's source of truth for translating Astryx to Flutter. Astryx is a React/StyleX design system; Var ports its visual and interaction contract to Material 3 instead of taking a runtime dependency.

Reference reviewed on 2026-07-26:

- https://astryx.atmeta.com/components
- https://astryx.atmeta.com/docs/principles
- https://astryx.atmeta.com/docs/tokens
- https://astryx.atmeta.com/docs/color
- https://astryx.atmeta.com/docs/typography
- https://astryx.atmeta.com/docs/spacing
- https://astryx.atmeta.com/docs/shape
- https://astryx.atmeta.com/docs/elevation
- https://astryx.atmeta.com/docs/motion
- https://astryx.atmeta.com/docs/layout
- https://github.com/facebook/astryx

Astryx code is MIT licensed, copyright 2026 Meta Platforms, Inc. Var's Flutter port must retain applicable notices for copied substantial code. Fonts and icons keep their own licenses. Do not use Astryx or Meta logos as Var branding.

## Product contract

- Full Astryx across shell, forms, data views, dialogs, canvas cards, onboarding, and lock screen.
- Supported themes: Neutral, Stone, Gothic, Matcha, Y2K, Butter, Chocolate.
- Neutral is fallback for unknown or retired stored variants.
- Dark remains default. Gothic is dark-only.
- Node-type colors are category accents for icons, dots, thin borders, and chart markers. They are not system status colors or large panel fills.
- Material 3 supplies behavior, semantics, focus, and platform adaptation. Custom widgets exist only where Material has no equivalent.

## Principles

1. Use themed components before raw primitives.
2. Use semantic tokens before hard-coded values.
3. Build every rest, hover, focus, pressed, selected, disabled, loading, and status state.
4. Use spacing and borders for hierarchy. Use cards only for independently movable, comparable, removable, or interactive units.
5. Keep one primary action per view.
6. Do not encode status with color alone.
7. Keep light and dark behavior equivalent.
8. Motion must explain state or spatial movement, never delay interaction.

## Neutral colors

| Role | Light | Dark |
|---|---:|---:|
| Accent | `#0064E0` | `#2694FE` |
| On accent | `#FFFFFF` | `#FFFFFF` |
| Accent muted | `#0082FB33` | `#0082FB3F` |
| App background | `#F1F4F7` | `#111112` |
| Surface/card | `#FFFFFF` | `#1F1F22` |
| Popover | `#FFFFFF` | `#28292C` |
| Text primary | `#0A1317` | `#DFE2E5` |
| Text secondary | `#4E606F` | `#AAAFB5` |
| Text disabled | `#A4B0BC` | `#6F747C` |
| Border | `#05365919` | `#F2F4F619` |
| Border strong | `#CCD3DB` | `#494D53` |
| Hover overlay | `#0536590C` | `#FFFFFF0C` |
| Pressed overlay | `#05365919` | `#FFFFFF19` |
| Scrim | `#01122866` | `#11111299` |
| Track/skeleton | `#CCD3DB` | `#5A5E66` |

Status roles:

| Role | Light | Dark | Muted light/dark | On color |
|---|---:|---:|---:|---:|
| Success | `#0D8626` | `#0D8626` | `#0B991F33` / `#0B991F3F` | `#FFFFFF` |
| Error | `#E3193B` | `#F5394F` | `#E3193B33` / `#F5394F3F` | `#FFFFFF` |
| Warning | `#E9AF08` | `#F2C00B` | `#E2A40033` / `#E2A4003F` | `#0A1317` |
| Info | Accent | Accent | Accent muted | On accent |

Normal text needs at least 4.5:1 contrast. Large text and UI indicators need at least 3:1.

## Typography

Use bundled theme fonts with system fallback. Never fetch fonts at runtime.

| Role | Size | Weight | Line box |
|---|---:|---:|---:|
| Display 1 | 42 | 400 | 52 |
| Display 2 | 35 | 400 | 44 |
| Display 3 | 29 | 400 | 36 |
| Heading 1 | 24 | 600 | 32 |
| Heading 2 | 20 | 600 | 28 |
| Heading 3 | 17 | 600 | 24 |
| Heading 4 | 14 | 600 | 20 |
| Heading 5 | 12 | 600 | 20 |
| Heading 6 | 10 | 600 | 16 |
| Body | 14 | 400 | 20 |
| Label | 14 | 500 | 20 |
| Supporting | 12 | 400 | 20 |
| Code | 14 | 400 | 20 |

Flutter `TextStyle.height` is `lineBox / fontSize`. Do not disable system text scaling. Body copy targets 65–75 characters per line.

Theme font families:

- Neutral: Figtree.
- Stone: Figtree body, Montserrat heading.
- Gothic: Fustat.
- Matcha: DM Sans body, Playwrite US Trad heading.
- Y2K: Poppins.
- Butter: Outfit.
- Chocolate: Albert Sans body, Fraunces heading.

## Spacing, shape, elevation, and motion

Spacing scale:

`0, 2, 4, 6, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, 48`

Control visual heights:

- Small: 28.
- Medium: 32.
- Large: 36.
- Interactive bounds: at least 44, ideally 48 on touch.

Radius:

- Inner: 4.
- Element: 8.
- Container: 12.
- Page/chat: 28.
- Full: stadium/9999.

Nested radius follows `innerRadius = max(0, outerRadius - padding)`.

Elevation is low and communicates stacking: base, dropdown, sticky, dialog, toast, tooltip. Prefer border plus surface for static structure. Astryx low/medium/high shadows use paired shadows rather than one large glow.

Motion:

- Fast: 175 ms.
- Medium: 410 ms.
- Slow: 975 ms.
- Curve: `Cubic(0.24, 1, 0.4, 1)`.
- Reduced motion: zero duration or instant/fade-only state change when `MediaQuery.disableAnimations` or `accessibleNavigation` is true.

## Responsive frame

- Up to 768 px: mobile drawer.
- 769–1024 px: compact navigation rail, 72 px.
- Above 1024 px: extended navigation rail, 256 px.
- Persistent inspector: desktop only, 340–420 px.
- Medium/mobile inspector: end overlay or sheet with focus trap and focus restoration.
- Use `LayoutBuilder` for nested regions. Use directional alignment and padding for RTL.

## Flutter mapping

| Astryx | Flutter |
|---|---|
| Primary/secondary/ghost action | `FilledButton`, `FilledButton.tonal`, `TextButton` |
| Icon action | `IconButton` with tooltip and semantic label |
| Segmented control | `SegmentedButton` |
| Field/selector/typeahead | `TextField`, `DropdownMenu`, `RawAutocomplete` |
| Card/clickable card | `Card`, `InkWell`, `Semantics` |
| Banner/status | `MaterialBanner` or composed semantic surface |
| Toast | `SnackBar` |
| Dialog | `AlertDialog`, `Dialog`, fullscreen route on mobile |
| Side/mobile navigation | `NavigationRail`, `NavigationDrawer` |
| Tabs | `TabBar` |
| Table/list | rows and lists; card per row only when row is an independent unit |
| Popover | `OverlayPortal`, `MenuAnchor`, or composited follower |
| Command palette | `Dialog`/fullscreen route plus search and keyboard actions |
| Resizable inspector | existing pointer logic plus keyboard-operable resize handle |

Do not add `AstryxButton`, `AstryxCard`, or other one-line wrappers around themed Material widgets.

## Accessibility contract

- Every control has an accessible name; icon-only controls also have a tooltip.
- Focus remains visible and follows logical traversal order.
- Custom painters have a semantic/list fallback.
- Drag operations have a non-drag action where possible.
- Status pairs color with text, icon, shape, or pattern.
- Search result count and important async changes use polite live-region semantics.
- Dialogs expose title, trap focus, close safely, and restore focus.
- Shared components support RTL, text scale 2.0, reduced motion, and 44–48 px targets.
- Tests use Flutter tap-target, label, contrast, semantics, keyboard, RTL, and reduced-motion checks.

## Implementation limits

- No React, StyleX, runtime Google Fonts, or new icon package.
- No domain, repository, sync-policy, route-URL, persistence-key, canvas-geometry, or gesture refactor during visual migration.
- No feature-level hard-coded colors except documented data visualization palettes and deterministic collaborator colors.
- No doodle border, paper texture, or PatrickHand after migration completes.
