# Frontend Design Standards

## Stack (Prescriptive Defaults)

No prior frontend experience — Claude picks the stack. Use this always:

| Layer | Tool |
|-------|------|
| Framework | React (Vite) |
| Styling | Tailwind CSS |
| Components | shadcn/ui |
| State | React hooks (useState, useReducer) |
| Data fetching | Axios or native fetch |
| Forms | react-hook-form + zod |

## Project Type

Primary use case: **CRUD interfaces** — forms, tables, data management UIs.

## Visual Style

- **Aesthetic:** Minimalism — clean, spacious, functional
- **Theme:** Dark mode always by default
- **Typography:** Sans-serif, clear hierarchy
- **Colors:** Muted palette, high contrast where needed
- **No decorative elements** that don't serve a function

## Layout & Responsive

- **Approach:** Desktop-first
- **Breakpoints:** Tailwind defaults (sm/md/lg/xl)
- **Min supported width:** 1024px desktop, graceful degradation to 768px tablet

## Component Rules

- Functional components only — no class components
- One component per file
- No inline styles — Tailwind utility classes only
- Keep components small and focused — split if >150 lines
- Name files in PascalCase: `UserTable.tsx`, `LoginForm.tsx`

## File Structure

```
src/
├── components/     # Reusable UI components
├── pages/          # Route-level components
├── hooks/          # Custom hooks
├── services/       # API calls
├── types/          # TypeScript interfaces
└── utils/          # Helper functions
```

## What Claude Should Never Do

- Write class-based React components
- Use inline CSS styles
- Hardcode API URLs — use environment variables
- Create components longer than 200 lines without splitting
- Add animations or decorative graphics unless explicitly asked
- Use a UI library other than shadcn/ui without asking first
