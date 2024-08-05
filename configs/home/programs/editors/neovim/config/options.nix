{
  programs.nixvim = {
    opts =
      let
        tabSize = 4;
      in
      {
        # Enable relative line numbers
        number = true;
        relativenumber = false;

        # Set tabs to tabSize spaces
        tabstop = tabSize;
        softtabstop = tabSize;
        showtabline = 2; # Always show tabs
        expandtab = true;

        # Enable auto indenting and set it to spaces
        smartindent = true;
        shiftwidth = tabSize;

        # Enable smart indenting
        breakindent = true;

        # Enable incremental searching
        hlsearch = true;
        incsearch = true;

        # text wrap
        wrap = false;

        # Better splitting
        splitbelow = true;
        splitright = true;

        # Enable mouse mode
        mouse = "a"; # Mouse

        # Enable ignorecase + smartcase for better searching
        ignorecase = true;
        smartcase = true; # Don't ignore case with capitals
        grepprg = "rg --vimgrep";
        grepformat = "%f:%l:%c:%m";

        # Decrease updatetime
        updatetime = 50; # faster completion (4000ms default)

        # Set completeopt to have a better completion experience
        completeopt = [
          "menuone"
          "noselect"
          "noinsert"
        ]; # mostly just for cmp

        # Enable persistent undo history
        swapfile = false;
        backup = false;
        undofile = true;

        # Enable 24-bit colors
        termguicolors = true;

        # Enable the sign column only if signs are present
        signcolumn = "auto";

        # Enable cursor line highlight
        cursorline = true; # Highlight the line where the cursor is located

        # Set fold settings
        # These options were reccommended by nvim-ufo
        # See: https://github.com/kevinhwang91/nvim-ufo#minimal-configuration
        foldcolumn = "0";
        foldlevel = 99;
        foldlevelstart = 99;
        foldenable = true;

        # Always keep 8 lines above/below cursor unless at start/end of file
        scrolloff = 8;

        # Place a column line
        colorcolumn = "80";

        # Reduce which-key timeout to 10ms
        timeoutlen = 10;

        # Set encoding type
        encoding = "utf-8";
        fileencoding = "utf-8";

        # Change cursor options
        guicursor = [
          "n-v-c:block" # Normal, visual, command-line: block cursor
          "i-ci-ve:block" # Insert, command-line insert, visual-exclude: vertical bar cursor with block cursor, use "ver25" for 25% width
          "r-cr:hor20" # Replace, command-line replace: horizontal bar cursor with 20% height
          "o:hor50" # Operator-pending: horizontal bar cursor with 50% height
          "a:blinkwait700-blinkoff400-blinkon250-Cursor/lCursor" # All modes: blinking settings
          "sm:block-blinkwait175-blinkoff150-blinkon175" # Showmatch: block cursor with specific blinking settings
        ];

        # Enable chars list
        list = true; # Show invisible characters (tabs, eol, ...)
        listchars = "eol:↲,tab:|->,lead:·,space: ,trail:•,extends:→,precedes:←,nbsp:␣";

        # More space in the neovim command line for displaying messages
        cmdheight = 2;

        # We don't need to see things like INSERT anymore
        showmode = false;

        # Maximum number of items to show in the popup menu (0 means "use available screen space")
        pumheight = 0;

        # Use conform-nvim for gq formatting. ('formatexpr' is set to vim.lsp.formatexpr(), so you can format lines via gq if the language server supports it)
        # formatexpr = "v:lua.require'conform'.formatexpr()";

        laststatus = 3; # (https://neovim.io/doc/user/options.html#'laststatus')
      };
  };
}
