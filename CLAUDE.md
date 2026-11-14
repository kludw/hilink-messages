# CLAUDE.md

## Documentation lookups

- Always use the Context7 MCP server (`resolve-library-id`, then `query-docs`) before writing or changing code that depends on a library, framework or any API. Do this even when the answer seems known; training data may be out of date.
- Pull the current docs by default. Ask Context7 for an older version only when the project is pinned to one.
- Use web search for library docs only when Context7 has nothing on that library.
