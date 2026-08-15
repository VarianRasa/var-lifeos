# Quote Discovery UI Polish Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Quote Discover into a responsive author library and editorial quote picker.

**Architecture:** Keep repository and state behavior inside the existing panel. Replace only presentation composition with local private widgets for author cards, quote cards, skeletons, error/empty states, and pagination. Increase Quote policy width to 820.

**Tech Stack:** Flutter Material 3, Riverpod, existing Quote catalog domain.

---

### Task 1: Author library
- [ ] Add responsive grid and deterministic initials avatars.
- [ ] Show author name and quote count.
- [ ] Add search clear, helper text, and static skeleton cards.
- [ ] Preserve debounced search and popular-author restoration.

### Task 2: Quote picker
- [ ] Add selected-author toolbar.
- [ ] Add editorial quote cards and provider metadata.
- [ ] Add bounded result viewport and Previous/Next pagination.
- [ ] Add polished error and empty states.

### Task 3: Geometry and tests
- [ ] Set expanded Quote width to 820.
- [ ] Add responsive grid, selection, pagination, and sizing tests.
- [ ] Run format, focused tests, and analyzer.