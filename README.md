# docent.nvim

AI-guided PR review walkthrough for Neovim.

docent.nvim runs an AI-powered code review via [OpenCode](https://opencode.ai) and presents
findings as a structured, navigable walkthrough inside Neovim. Three synchronized panels --
findings list, diff view, and explanation note -- let you step through each finding,
understand the what/why/learning behind it, ask follow-up questions, and take action
directly on the PR.

```
┌───────────────────────────────────────────────────────────────┐
│ Findings       │                                              │
│                │  @@ -42,6 +42,9 @@                         │
│  ▸✓!! 1  Token │    func validateToken(tok string) error {    │
│    ✗ ! 2  Race │  +   if tok == "" {                          │
│      ~ 3  Name │  +     return nil  // ← bug: empty ≠ valid  │
│      ? 4  Why  │  +   }                                      │
│      + 5  Good │    claims, err := parseJWT(tok)              │
│                │                                              │
├───────────────────────────────────────────────────────────────┤
│  WHAT                                                         │
│  Empty token strings bypass validation entirely because the   │
│  guard clause returns nil instead of an error.                │
│                                                               │
│  LEARNING                                                     │
│  Distinguish between "absent" and "invalid" inputs at the     │
│  boundary of every validation function.                       │
│                                                               │
│  SUGGESTION                                                   │
│  return fmt.Errorf("token must not be empty")                 │
└───────────────────────────────────────────────────────────────┘
```

## Features

- **Structured walkthrough** -- findings sorted by severity (bug > warning > style > question > positive > info) with synchronized three-panel navigation
- **Rich context** -- each finding shows the relevant diff with highlighted focus lines, plus a detailed explanation, learning, and optional suggestion
- **Follow-up questions** -- ask the AI about any finding; per-finding chat history is preserved in a split panel
- **PR actions** -- acknowledge/dismiss findings, post inline comments, approve, or request changes without leaving Neovim
- **Full diff view** -- floating window showing the entire PR diff with gutter signs marking every finding
- **Summary view** -- floating window with PR metadata, assessment, and a findings breakdown by category
- **Session persistence** -- save reviews to disk and resume them later, even across Neovim restarts
- **Git state management** -- automatically stashes changes, checks out the PR branch, and restores everything on close
- **OpenCode terminal** -- attach the OpenCode TUI directly in the diff panel to interact with the AI session
- **Async throughout** -- all git, GitHub, and AI operations are non-blocking

## Requirements

- Neovim >= 0.9
- [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- [gh CLI](https://cli.github.com) -- authenticated (`gh auth login`)
- [OpenCode](https://opencode.ai) -- installed and configured

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "68mschmitt/docent.nvim",
  dependencies = { "nvim-lua/plenary.nvim" },
  config = function()
    require("docent").setup()
  end,
}
```

### [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "68mschmitt/docent.nvim",
  requires = { "nvim-lua/plenary.nvim" },
  config = function()
    require("docent").setup()
  end,
}
```

### [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'nvim-lua/plenary.nvim'
Plug '68mschmitt/docent.nvim'
```

```lua
require("docent").setup()
```

## Configuration

`setup()` accepts an optional table. All values shown below are the defaults:

```lua
require("docent").setup({
  -- OpenCode server. nil = auto-detect a running server or start one.
  opencode_url = nil,
  opencode_cmd = "opencode",  -- path to the opencode binary
  opencode_port = 19847,      -- port used when auto-starting the server

  -- GitHub CLI
  gh_cmd = "gh",              -- path to the gh binary

  -- Layout dimensions
  layout = {
    finding_list_width = 34,  -- columns for the findings list panel
    note_panel_height  = 12,  -- lines for the note panel
    chat_panel_width   = 50,  -- percentage of note panel width when chat is open
  },

  -- Show keymap hints in panel footers
  show_keymaps = true,

  -- System prompt sent to the AI for the review.
  -- Override this to change the review style or focus areas.
  review_prompt = "You are a senior code reviewer and mentor. ...",

  -- Optional model override. nil = use OpenCode default.
  -- model = { providerID = "anthropic", modelID = "claude-sonnet-4-20250514" },
  model = nil,

  -- Directory for saved reviews
  data_dir = vim.fn.stdpath("data") .. "/docent",
})
```

## Usage

### Starting a Review

```vim
" Open a picker to select from open PRs in the current repo
:DocentReview

" Start directly with a PR reference
:DocentReview #123
:DocentReview owner/repo#123
:DocentReview https://github.com/owner/repo/pull/123
```

The review pipeline runs automatically:

1. Stashes uncommitted changes and checks out the PR branch
2. Connects to the OpenCode server (auto-starting if needed)
3. Fetches PR metadata and the full diff
4. Sends the diff for AI review
5. Parses structured findings and opens the walkthrough

During steps 2-5 you can watch the AI work in real time -- the OpenCode
terminal is shown in the diff panel until the review completes.

### Navigating Findings

Once the walkthrough opens, use the keymaps below to step through findings.
All three panels stay synchronized: selecting a finding updates the diff to
show the relevant file with focus lines highlighted, and the note panel
displays the explanation.

### Taking Action

- **Acknowledge** (`a`) -- mark a finding as reviewed
- **Dismiss** (`d`) -- mark a finding as not applicable
- **Comment** (`c`) -- post an inline comment to the PR on GitHub
- **Follow-up** (`?`) -- ask the AI a question about the current finding; the response appears in a chat split
- **Approve** (`:DocentApprove`) -- submit an approving review
- **Request changes** (`:DocentRequestChanges`) -- submit a request-changes review

### Saving and Resuming

```vim
:DocentSave           " save the current review to disk
:DocentHide           " hide the layout but keep the session in memory
:DocentResume         " reopen a hidden session, or load the latest saved review
:DocentLoad           " pick from all saved reviews
:DocentLoad path.json " load a specific saved review file
```

Saved reviews are stored as JSON in `data_dir` (default: `stdpath("data")/docent/`).

## Commands

| Command | Description |
|---|---|
| `:DocentReview [ref]` | Start a review. No args opens a PR picker. |
| `:DocentSummary` | Show PR summary in a floating window. |
| `:DocentDiff` | Show full diff with finding markers in a floating window. |
| `:DocentApprove` | Approve the PR (prompts for optional message). |
| `:DocentRequestChanges` | Request changes (prompts for message). |
| `:DocentClose` | Close the review and restore the original branch. |
| `:DocentHide` | Hide the layout without destroying the session. |
| `:DocentResume` | Resume a hidden or saved review. |
| `:DocentSave` | Save the current review to disk. |
| `:DocentLoad [file]` | Load a saved review. No args opens a picker. |
| `:DocentAttach` | Toggle the OpenCode terminal in the diff panel. |

## Keymaps

All keymaps are buffer-local to the walkthrough panels.

### All Panels

| Key | Action |
|---|---|
| `q` | Hide the review |
| `Q` | Close the review and restore branch |
| `c` | Post a comment on the current finding |
| `?` | Ask a follow-up question |
| `<C-d>` | Scroll the note panel down |
| `<C-u>` | Scroll the note panel up |

### Findings List

| Key | Action |
|---|---|
| `j` / `k` | Next / previous finding |
| `<CR>` | Focus the diff panel |
| `a` | Acknowledge the current finding |
| `d` | Dismiss the current finding |
| `S` | Open the summary window |
| `D` | Open the full diff window |
| `1`-`9` | Jump to finding N |

### Diff View

| Key | Action |
|---|---|
| `]c` / `[c` | Next / previous finding |
| `]f` / `[f` | Next / previous file with findings |
| `<Tab>` | Focus the findings list |

### Note Panel

| Key | Action |
|---|---|
| `j` / `k` | Scroll the note |
| `<C-d>` / `<C-u>` | Scroll the note 5 lines |
| `a` | Acknowledge the current finding |
| `d` | Dismiss the current finding |
| `<Tab>` | Focus the findings list |
| `<Esc>` | Close the chat split |

## Highlight Groups

All highlight groups are defined with `default = true`, so your colorscheme
takes precedence. Override any group in your config to customize the
appearance.

### Finding Categories

| Group | Default | Description |
|---|---|---|
| `DocentBug` | `#e06c75` bold | Bug findings |
| `DocentWarning` | `#e5c07b` bold | Warning findings |
| `DocentStyle` | `#6b7280` | Style findings |
| `DocentQuestion` | `#61afef` | Question findings |
| `DocentPositive` | `#98c379` bold | Positive findings |
| `DocentInfo` | `#56b6c2` | Informational findings |

### Finding Statuses

| Group | Default | Description |
|---|---|---|
| `DocentPending` | `#abb2bf` | Unreviewed finding |
| `DocentAcknowledged` | `#98c379` | Acknowledged finding |
| `DocentDismissed` | `#6b7280` strikethrough | Dismissed finding |

### Diff

| Group | Default | Description |
|---|---|---|
| `DocentDiffAdd` | `#98c379` | Added lines |
| `DocentDiffDel` | `#e06c75` | Deleted lines |
| `DocentDiffHunk` | `#c678dd` | Hunk headers |
| `DocentDiffFile` | `#61afef` bold | File headers |
| `DocentDiffFocusLine` | bg `#2a2e36` bold | Current finding's lines |
| `DocentDiffFocusAdd` | `#98c379` on `#2a2e36` bold | Focused added line |
| `DocentDiffFocusDel` | `#e06c75` on `#2a2e36` bold | Focused deleted line |
| `DocentDiffOtherMark` | `#6b7280` underline | Other findings in same file |

### UI

| Group | Default | Description |
|---|---|---|
| `DocentCurrent` | `#c678dd` bold | Current finding indicator |
| `DocentHeader` | `#abb2bf` bold underline | Panel headers |
| `DocentHeaderAccent` | `#61afef` bold | Header accent text |
| `DocentKeyHint` | `#6b7280` | Keymap hint text |
| `DocentKey` | `#e5c07b` | Keymap key text |
| `DocentNoteSection` | `#c678dd` bold | Note section headers (WHAT, LEARNING, ...) |
| `DocentNoteText` | `#abb2bf` | Note body text |
| `DocentChatUser` | `#61afef` bold | User messages in chat |
| `DocentChatAI` | `#98c379` | AI responses in chat |
| `DocentStatusActive` | `#98c379` bold | Active review indicator |
| `DocentStatusCount` | `#e5c07b` | Finding count |
| `DocentLoading` | `#6b7280` italic | Loading / progress text |

### Signs

| Sign | Text | Description |
|---|---|---|
| `DocentBugSign` | `!!` | Bug marker in gutter |
| `DocentWarningSign` | `! ` | Warning marker |
| `DocentStyleSign` | `~ ` | Style marker |
| `DocentQuestionSign` | `? ` | Question marker |
| `DocentPositiveSign` | `+ ` | Positive marker |
| `DocentInfoSign` | `i ` | Info marker |

## How It Works

```
:DocentReview #42
       │
       ▼
┌─────────────────┐     ┌──────────────┐     ┌───────────────┐
│  git stash +    │────▶│  Connect to  │────▶│  Fetch PR     │
│  checkout PR    │     │  OpenCode    │     │  info + diff  │
└─────────────────┘     └──────────────┘     └───────┬───────┘
                                                     │
       ┌─────────────────────────────────────────────┘
       ▼
┌─────────────────┐     ┌──────────────┐     ┌───────────────┐
│  Create AI      │────▶│  AI reviews  │────▶│  Parse into   │
│  session        │     │  the diff    │     │  findings     │
└─────────────────┘     └──────────────┘     └───────┬───────┘
                                                     │
       ┌─────────────────────────────────────────────┘
       ▼
┌─────────────────────────────────────────────────────────────┐
│                    Walkthrough opens                         │
│                                                             │
│  Findings List  ──sync──  Diff View  ──sync──  Note Panel  │
│                                                             │
│  Navigate, acknowledge, dismiss, comment, ask follow-ups,  │
│  approve, or request changes.                               │
└─────────────────────────────────────────────────────────────┘
       │
       ▼
┌─────────────────┐
│  :DocentClose   │──▶  restore branch + pop stash
└─────────────────┘
```

## License

MIT
