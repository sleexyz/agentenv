set mouse=a
set hidden
syntax on
filetype plugin indent on
set backupdir=~/.config/nvim/tmp//
set directory=~/.config/nvim/tmp//
set tabstop=2 softtabstop=2 shiftwidth=2 expandtab
set showmatch
set matchtime=5
set laststatus=2
set showcmd
set ignorecase
set smartcase
set incsearch
set splitbelow
set splitright
set backspace=indent,eol,start

imap jk <Esc>
set termguicolors

set background=dark
highlight Normal guibg=NONE ctermbg=NONE
highlight NormalNC guibg=NONE ctermbg=NONE
highlight EndOfBuffer guibg=NONE ctermbg=NONE
highlight SignColumn guibg=NONE ctermbg=NONE

" Auto-reload files changed outside vim
set autoread
autocmd FocusGained,BufEnter * checktime
set updatetime=1000
