# Design Spec: Material 3 Adaptive, Shadcn-Inspired UI System

## Status

Approved in conversation on 2026-08-08.

## Goal

Polish every user-facing surface in Var across Android, iOS, Web, Windows, macOS, and Linux with one coherent system:

- Material 3 provides native Flutter components, semantics, focus, input behavior, and platform adaptation.
- shadcn/ui provides visual direction: neutral hierarchy, semantic foreground and surface roles, border-first structure, compact controls, restrained elevation, clear focus rings, and composable content.
- Existing seven Astryx variants continue to provide color palettes and font families.

This is a visual and interaction-system migration. Domain logic, persistence, routes, canvas coordinates, selection geometry, gestures, synchronization, and backup behavior remain unchanged.

## Sources

- Flutter ships Material and Cupertino design systems and recommends deliberate adaptive choices while preserving platform-correct behavior: https://docs.flutter.dev/ui/adaptive-responsive/platform-adaptations
- Flutter Material 3 migration uses `ThemeData` and `ColorScheme`: https://docs.flutter.dev/release/breaking-changes/material-3-migration
- shadcn/ui is open code built around composition and accessible defaults rather than a conventional runtime component library: https://ui.shadcn.com/docs
- shadcn/ui semantic theme roles include background, foreground, card, popover, primary, secondary, muted, accent, destructive, border, input, and ring: https://ui.shadcn.com/docs/theming
- Official shadcn/ui installation targets web frameworks, not Flutter: https://ui.shadcn.com/docs/installation
- Official component inventory: https://ui.shadcn.com/docs/components

## Architecture

### One Source of Truth

`ThemeData`, `AppSemanticColors`, and `AppDesignTokens` remain the only global design-system sources.

- `AppThemeVariantColors` owns each Astryx variant's light/dark colors.
- Existing font mapping owns each Astryx variant's typography family.
- `AppSemanticColors` maps palette values to component-independent roles.
- `AppDesignTokens` owns shared spacing, radii, control sizing, motion, and elevation.
- `AppTheme.forVariant` translates these values into Material component themes.

No parallel `ShadcnTheme`, CSS token tree, React runtime, web component layer, or `Shadcn*` widget family will be added.

### Native Components First

Use Flutter Material components for behavior and semantics:

- `FilledButton`, `OutlinedButton`, `TextButton`, and `IconButton`
- `TextField`, `DropdownMenu`, `Checkbox`, `Radio`, `Switch`, and `Slider`
- `Card`, `ListTile`, `Dialog`, `BottomSheet`, `MenuAnchor`, and `PopupMenuButton`
- `NavigationDrawer`, `NavigationRail`, `NavigationBar`, `TabBar`, and `SegmentedButton`
- `Tooltip`, `SnackBar`, `MaterialBanner`, and progress indicators

Shared widgets remain only when they add meaningful composition or behavior, such as status semantics, keyboard hints, selectable surfaces, empty states, or skeleton loading. One-line visual wrappers are removed progressively rather than renamed.

## Visual Contract

### Color

Seven Astryx palettes and fonts remain selectable. Each palette must expose equivalent semantic roles:

- background and foreground
- card and card foreground
- popover and popover foreground
- primary and primary foreground
- secondary and secondary foreground
- muted and muted foreground
- accent and accent foreground
- destructive and destructive foreground
- border, input border, and focus ring

Node-type colors remain data accents only: icons, dots, slim edges, chart marks, and canvas identities. They do not replace structural surfaces.

### Shape and Elevation

- Controls use tight, consistent radii.
- Containers use a slightly larger radius than controls.
- Large page rounding is reserved for deliberate sheets or major surfaces, not every panel.
- Static hierarchy uses surface contrast and one-pixel borders.
- Cards default to zero elevation.
- Menus, popovers, dialogs, and dragged elements may use restrained elevation.
- Decorative paper textures, doodle borders, and ornamental shadows are retired.

### Density and Touch

- Visual controls may be compact on desktop and web.
- Interactive targets remain at least 44 logical pixels.
- Mobile layouts prioritize touch spacing and safe areas.
- Desktop/web layouts support pointer hover, keyboard focus, shortcuts, scrolling, and context menus.

### Typography

- Astryx font families remain unchanged.
- Material text roles define hierarchy and scaling.
- Feature widgets stop inventing local title/body sizes when a theme role exists.
- System text scaling remains enabled.
- Truncation is allowed only where full content remains available through expansion, tooltip, detail view, or accessible label.

### States

Every interactive component supports applicable states:

- enabled
- hovered
- focused
- pressed
- selected
- disabled
- loading
- invalid
- destructive

Focus must remain visible. Status and errors cannot rely on color alone.

## Adaptive Layout Contract

Layout adapts by available space and input model, not OS name alone.

- Compact: single-column flow, mobile header/navigation, bottom sheets where appropriate, touch-first actions.
- Medium: compact navigation plus flexible content regions.
- Expanded: persistent navigation and optional inspector/detail panes.
- Nested components use `LayoutBuilder` and content-driven thresholds.
- Tables may scroll horizontally or reduce optional columns; rows are not automatically converted into excessive cards.
- Dialogs may become full-screen or bottom sheets on compact screens and constrained dialogs on expanded screens.

Platform-correct text editing, scrolling, keyboard behavior, route transitions, and window controls remain native/adaptive.

## Component Mapping

| shadcn/ui concept | Flutter implementation |
|---|---|
| Button variants | Material filled, outlined, text, icon button themes |
| Card | Native `Card` with border-first theme |
| Input / Textarea | `TextField` and `InputDecorationTheme` |
| Field / Label | Form composition using visible labels, helper and error text |
| Select / Combobox | `DropdownMenu`, menu anchors, searchable custom composition where required |
| Checkbox / Radio / Switch | Native themed Material controls |
| Dialog / Alert Dialog | `Dialog` or `AlertDialog` with adaptive constraints |
| Sheet / Drawer | Modal bottom sheet, drawer, or side panel by available width |
| Dropdown / Context Menu | `MenuAnchor` or `PopupMenuButton` |
| Command | Existing command palette behavior with restyled surfaces and rows |
| Tabs / Toggle Group | `TabBar`, `SegmentedButton`, or focused custom composition |
| Table / Data Table | Existing Flutter table/list views with semantic row actions |
| Alert / Toast | `MaterialBanner`, inline status surface, and `SnackBar` |
| Skeleton / Empty | Existing reduced-motion shared widgets |
| Tooltip / Kbd | Native tooltip and shared keyboard-hint presentation |
| Calendar / Date Picker | Existing calendar domain UI and Material date interactions |
| Chart | Existing painters and data colors; only surrounding chrome changes |

Components without an app use case are not created preemptively. Coverage means every existing app component receives the system, not that unused shadcn catalog entries are cloned.

## Migration Phases

### Phase 1: Foundation

- Resolve current token, documentation, and test mismatches.
- Establish shadcn-inspired geometry, border, surface, elevation, and state rules.
- Complete Material component themes.
- Keep seven Astryx palettes and fonts working in light/dark modes.

### Phase 2: Shared Components and Shell

- Audit Astryx wrappers and keep only behavior-rich primitives.
- Remove local typography and colors from shared widgets.
- Polish adaptive shell, navigation, desktop chrome, search, status, empty, error, and loading surfaces.

### Phase 3: Standard Product Surfaces

- Settings, search, capture, focus, onboarding, sync/recovery.
- Forms, lists, dialogs, menus, filters, confirmations, and destructive actions.

### Phase 4: Dashboards and Data Views

- Insights, Life OS, workspace lists and non-canvas detail views.
- Cards, tables, charts, filters, badges, tabs, Kanban chrome, and responsive hierarchy.

### Phase 5: Calendar and Workspace

- Calendar pages, DayPage panels, headers, toolbars, tables, boards, and overlays.
- Workspace canvas chrome and data views.
- Preserve scheduling logic, drag/drop behavior, and geometry.

### Phase 6: Mindmap and Graph

- Node editors, inspectors, toolbars, popovers, media cards, and canvas overlays.
- Graph controls and detail panels.
- Preserve painters, transforms, hit testing, connectors, physics, and gestures unless a visual-only token change is safe.

### Phase 7: Deep Polish and Cleanup

- Remove obsolete ornamental visuals and dead wrappers.
- Audit raw colors, arbitrary radii, spacing, and typography.
- Verify responsive layouts, keyboard flows, focus restoration, semantics, RTL, text scaling, and reduced motion.

## Testing and Quality Gates

Each phase must leave the repository usable and independently reviewable.

Automated gates:

```bash
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

Focused tests accompany changed components. Visual behavior is checked at representative widths near 320, 768, 1024, and 1440 logical pixels. Critical flows also cover:

- light and dark modes
- all seven Astryx variants
- keyboard-only operation
- pointer hover and context actions
- touch targets and safe areas
- text scaling
- reduced motion
- semantics for custom controls and painters
- loading, empty, error, disabled, and destructive states

Golden tests may be used selectively for stable primitives, but behavior and accessibility tests remain authoritative.

## Risk Controls

- Existing uncommitted work must not be overwritten or bundled accidentally.
- Theme changes land before broad feature edits so global impact is observable.
- High-risk canvas pages migrate last.
- No bulk search-and-replace of colors or radii without classifying data visualization and geometry uses.
- Sync, recovery, and destructive flows retain explicit confirmations and status messaging.
- Large pages are migrated by cohesive component cluster, not rewritten wholesale.

## Acceptance Criteria

- Seven Astryx color/font variants remain available and visually distinct.
- All app surfaces use one Material 3 adaptive component language inspired by shadcn/ui.
- No shadcn web dependency or duplicate design-system runtime exists.
- Existing feature behavior and data remain intact.
- Compact, medium, and expanded layouts remain usable across supported platforms.
- Keyboard, pointer, touch, semantics, text scaling, and reduced-motion requirements pass.
- Repository format, analyzer, and tests pass at completion.
