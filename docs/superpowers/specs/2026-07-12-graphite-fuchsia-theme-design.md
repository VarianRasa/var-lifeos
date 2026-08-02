# Graphite Fuchsia Theme Design

Date: 2026-07-12
Status: Approved design, pending implementation

## Goal

Make Graphite Fuchsia the default Var palette. Provide matching dark and light themes with professional, simple, minimal visual hierarchy.

## Dark Tokens

- Canvas background: `#0B0B0F`
- App surface: `#121218`
- Raised surface: `#191920`
- Toolbar surface: `#15151C`
- Input surface: `#1D1D26`
- Border subtle: `#2A2A35`
- Border strong: `#3A3A48`
- Text primary: `#F4F2F6`
- Text secondary: `#B8B4C0`
- Text muted: `#7E7987`
- Disabled: `#595562`
- Primary: `#D946EF`
- Primary hover: `#E879F9`
- Primary pressed: `#C026D3`
- Primary container: `#3B123F`
- On primary: `#FFFFFF`
- Success: `#34D399`
- Warning: `#FBBF24`
- Error: `#FB7185`
- Info: `#60A5FA`

## Light Tokens

- Canvas background: `#F6F5F7`
- App surface: `#FFFFFF`
- Raised surface: `#FFFFFF`
- Toolbar surface: `#FAF9FB`
- Input surface: `#F3F1F5`
- Border subtle: `#E3DFE7`
- Border strong: `#C9C3CF`
- Text primary: `#211E24`
- Text secondary: `#625C68`
- Text muted: `#8C8492`
- Disabled: `#B7B0BC`
- Primary: `#C026D3`
- Primary hover: `#A21CAF`
- Primary pressed: `#86198F`
- Primary container: `#FAE8FF`
- On primary: `#FFFFFF`
- Success: `#059669`
- Warning: `#D97706`
- Error: `#E11D48`
- Info: `#2563EB`

## Component Rules

- Global radius is 10 logical pixels; dialogs and popovers use 14.
- Toolbar uses a solid surface and subtle one-pixel bottom border.
- Primary buttons use solid fuchsia. Secondary buttons use neutral surface and subtle border. Tertiary actions remain borderless.
- Node cards use neutral surfaces. Type colors appear only in icons or small chips. Selection uses a two-pixel fuchsia border and minimal shadow.
- Inputs use filled surfaces. Borders appear for focus and errors. Focus ring uses fuchsia.
- Tabs use neutral defaults and fuchsia container/indicator when selected. Remove neon green boxed styling.
- Chips are neutral by default and use fuchsia container when selected.
- Canvas grid and connectors remain neutral. Selected connectors use fuchsia.
- PatrickHand is optional accent typography only. Toolbar, forms, buttons, and metadata use professional sans-serif typography.
- Motion lasts 120-180 ms without bounce, strong glow, or decorative neon.

## Theme Behavior

- Graphite Fuchsia becomes the default theme variant.
- Dark remains the default mode unless existing user preference says otherwise.
- Existing alternate theme variants remain selectable.
- Semantic success, warning, error, and info colors remain distinct from primary fuchsia.
- Existing theme preference migration must preserve saved user choices.

## Validation

- Theme controller defaults to Graphite Fuchsia for new preferences.
- Dark and light ColorSchemes expose approved tokens.
- Toolbar, buttons, inputs, tabs, chips, dialog, and cards use shared theme configuration.
- Mindmap canvas, selected nodes, grid, connectors, and minimap use new palette.
- Existing theme and settings tests are updated.
- Run formatter, focused theme/settings/mindmap tests, and analyzer.
