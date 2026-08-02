# Quote Discovery UI Polish Design

## Goal

Polish Quote Discover into a readable author library and editorial quote picker while preserving manual editing, autosave, keyboard input, and existing backend behavior.

## Expanded Geometry

- Quote expanded width becomes 820 pixels.
- Height remains content-derived through `InlineNodeWorkspacePolicy`.
- Expanded Quote remains non-resizable.
- Catalog content receives a bounded internal viewport so large author and quote result sets do not expand the canvas node indefinitely.

## Structure

The Quote editor remains one vertical workspace:

1. Existing title field.
2. Existing content field.
3. Discover/Write manually mode control.
4. Discover catalog or manual Quote fields.

Discover catalog contains:

1. Section heading and short helper text.
2. Search field with search icon, clear action, and result count.
3. Author library grid or selected-author toolbar.
4. Scrollable author/quote result viewport.
5. Pagination controls when needed.

Mode control and search remain outside the result viewport so they stay visible while browsing.

## Author Library

Use a responsive `GridView`:

- 3 columns at wide Quote width;
- 2 columns below 620 pixels;
- 1 column below 400 pixels.

Each author card contains:

- deterministic initials avatar;
- author name with two-line maximum;
- quote count label;
- subtle selected/hover/focus states;
- full-card tap target;
- semantic button label.

Cards use Material 3 surface-container colors, restrained borders, and Quote node accent color.

## Selected Author

Replace the author grid with a toolbar containing:

- Back button;
- initials avatar;
- author name;
- quote count;
- current page summary.

The toolbar remains above the quote list.

## Quote Cards

Each quote result uses an editorial card:

- decorative quote icon;
- quote text with readable line height and maximum lines;
- author attribution;
- provider/source label;
- optional tags;
- full-width `Use this quote` action on narrow layouts;
- trailing or bottom-aligned action on wide layouts.

Selecting a quote keeps existing behavior: body and structured attribution update, autosave runs, and editor switches to Write manually.

## Loading, Error, and Empty States

- Author loading: six skeleton author cards.
- Quote loading: three skeleton quote cards.
- Error: outlined status card with error icon, short safe message, Retry, and Write manually action.
- Empty author search: search icon, `No authors found`, and suggestion to try a shorter name.
- Empty quote list: quote icon, author-specific message, and Back action.
- Unsupported/unconfigured endpoint: neutral setup message; manual mode remains available.

Skeletons are static tinted placeholders; no shimmer dependency.

## Pagination

Quote results show:

- Previous button when page > 1;
- `Page X of Y` label;
- Next button when `hasNextPage` is true.

Buttons disable while loading. Author search pagination remains hidden until the backend returns more than one page; initial implementation keeps author search page 1 to avoid extra UI complexity.

## Interaction and Accessibility

- Search debounce remains 350 milliseconds.
- Clear search restores popular authors.
- Enter in search field immediately executes search.
- Focus order follows mode, search, author cards, quote cards, pagination.
- Interactive controls keep at least 44-pixel logical tap height.
- Text truncation uses tooltips where author names or quotes are clipped.
- Colors use theme surfaces and maintain readable contrast.
- No hover-only functionality.

## Files

- Modify `lib/features/mindmap/presentation/node_editors/quote_discovery_panel.dart`.
- Modify `lib/features/mindmap/domain/inline_node_workspace_policy.dart`.
- Extend `test/features/mindmap/presentation/quote_discovery_panel_test.dart`.
- Extend Quote sizing tests in `test/features/mindmap/presentation/mindmap_canvas_test.dart`.

No new dependency or reusable design-system abstraction is added.

## Validation

Tests cover:

- responsive author grid column count;
- author initials and quote count;
- selected-author toolbar;
- editorial quote card and Use action;
- search clear behavior;
- author and quote loading states;
- error and empty states;
- Previous/Next pagination;
- expanded Quote width 820 and no resize controls;
- no overflow at narrow catalog constraints.

## Deliberate Limits

No author images, animations, shimmer package, infinite scroll, saved searches, sorting, filters, or shared component library extraction.