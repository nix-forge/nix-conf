{
  render = { palette }: {
    "$schema" = "vscode://schemas/color-theme";
    name = "Carbon Neon";
    type = "dark";
    semanticHighlighting = true;
    colors = {
      focusBorder = "#${palette.accent}";
      foreground = "#${palette.text}";
      descriptionForeground = "#${palette.text}B3";
      errorForeground = "#${palette.danger}";
      "widget.shadow" = "#${palette.surface}99";
      "textLink.foreground" = "#${palette.accent}";
      "textLink.activeForeground" = "#${palette.success}";
      "textCodeBlock.background" = "#${palette.surfaceHover}";
      "selection.background" = "#${palette.accent}40";
      "textPreformat.foreground" = "#${palette.info}";
      "button.background" = "#${palette.accent}";
      "button.foreground" = "#${palette.surface}";
      "button.hoverBackground" = "#${palette.success}";
      "button.secondaryBackground" = "#${palette.surfaceHover}";
      "button.secondaryForeground" = "#${palette.text}";
      "button.secondaryHoverBackground" = "#${palette.outline}";
      "badge.background" = "#${palette.accent}";
      "badge.foreground" = "#${palette.surface}";
      "activityBarBadge.background" = "#${palette.accent}";
      "activityBarBadge.foreground" = "#${palette.surface}";
      "progressBar.background" = "#${palette.accent}";
      "input.background" = "#${palette.surfaceHover}";
      "input.foreground" = "#${palette.text}";
      "input.border" = "#${palette.scrollbar}";
      "input.placeholderForeground" = "#${palette.text}B3";
      "inputOption.activeBorder" = "#${palette.accent}";
      "inputOption.activeBackground" = "#${palette.accent}26";
      "inputValidation.infoBackground" = "#${palette.surfaceHover}";
      "inputValidation.infoBorder" = "#${palette.info}";
      "inputValidation.warningBackground" = "#${palette.surfaceHover}";
      "inputValidation.warningBorder" = "#${palette.warning}";
      "inputValidation.errorBackground" = "#${palette.surfaceHover}";
      "inputValidation.errorBorder" = "#${palette.danger}";
      "dropdown.background" = "#${palette.surfaceHover}";
      "dropdown.border" = "#${palette.scrollbar}";
      "menu.background" = "#${palette.surfaceHover}";
      "menu.foreground" = "#${palette.text}";
      "menu.selectionBackground" = "#${palette.outline}";
      "menu.selectionForeground" = "#${palette.textStrong}";
      "menu.separatorBackground" = "#${palette.outline}";
      "editorWidget.background" = "#${palette.surfaceHover}";
      "editorWidget.foreground" = "#${palette.text}";
      "editorWidget.border" = "#${palette.scrollbar}";
      "quickInput.background" = "#${palette.surfaceHover}";
      "quickInput.foreground" = "#${palette.text}";
      "pickerGroup.border" = "#${palette.outline}";
      "pickerGroup.foreground" = "#${palette.accent}";
      "keybindingLabel.background" = "#${palette.surfaceRaised}";
      "keybindingLabel.foreground" = "#${palette.text}";
      "keybindingLabel.border" = "#${palette.outlineSubtle}";
      "keybindingLabel.bottomBorder" = "#${palette.outline}";
      "notifications.background" = "#${palette.surfaceHover}";
      "notifications.foreground" = "#${palette.text}";
      "notifications.border" = "#${palette.scrollbar}";
      "notificationLink.foreground" = "#${palette.accent}";
      "notificationsErrorIcon.foreground" = "#${palette.danger}";
      "notificationsWarningIcon.foreground" = "#${palette.warning}";
      "notificationsInfoIcon.foreground" = "#${palette.info}";
      "notificationCenter.border" = "#${palette.outline}";
      "notificationCenterHeader.background" = "#${palette.surfaceRaised}";
      "notificationCenterHeader.foreground" = "#${palette.text}";
      "banner.background" = "#${palette.surfaceHover}";
      "banner.foreground" = "#${palette.text}";
      "banner.iconForeground" = "#${palette.accent}";
      "titleBar.activeBackground" = "#${palette.surface}";
      "titleBar.activeForeground" = "#${palette.text}";
      "titleBar.inactiveBackground" = "#${palette.surface}";
      "titleBar.inactiveForeground" = "#${palette.muted}";
      "titleBar.border" = "#${palette.surfaceHover}";
      "activityBar.background" = "#${palette.surface}";
      "activityBar.foreground" = "#${palette.text}";
      "activityBar.inactiveForeground" = "#${palette.muted}";
      "activityBar.activeBorder" = "#${palette.accent}";
      "activityBarTop.background" = "#${palette.surfaceChrome}";
      "activityBarTop.foreground" = "#${palette.text}";
      "activityBarTop.inactiveForeground" = "#${palette.muted}";
      "activityBarTop.activeBorder" = "#${palette.accent}B3";
      "sideBar.background" = "#${palette.surface}";
      "sideBar.foreground" = "#${palette.text}";
      "sideBar.border" = "#${palette.outline}";
      "sideBarSectionHeader.background" = "#${palette.surfaceRaised}";
      "sideBarSectionHeader.foreground" = "#${palette.text}";
      "editorGroup.border" = "#${palette.outline}";
      "editorGroupHeader.tabsBackground" = "#${palette.surfaceChrome}";
      "editorGroupHeader.tabsBorder" = "#${palette.surfaceHover}";
      "tab.activeBackground" = "#${palette.surface}";
      "tab.activeForeground" = "#${palette.textStrong}";
      "tab.activeBorderTop" = "#${palette.accent}B3";
      "tab.inactiveBackground" = "#${palette.surfaceChrome}";
      "tab.inactiveForeground" = "#${palette.muted}";
      "editor.background" = "#${palette.surface}";
      "editor.foreground" = "#${palette.text}";
      "editorCursor.foreground" = "#${palette.cursor}";
      "editor.selectionBackground" = "#${palette.accent}40";
      "editor.inactiveSelectionBackground" = "#${palette.accent}26";
      "editor.lineHighlightBackground" = "#${palette.surfaceRaised}";
      "editor.findMatchBackground" = "#${palette.warning}40";
      "editor.findMatchBorder" = "#${palette.warning}";
      "editor.findMatchHighlightBackground" = "#${palette.warning}26";
      "editor.findRangeHighlightBackground" = "#${palette.warning}14";
      "editorLineNumber.foreground" = "#${palette.lineNumber}";
      "editorLineNumber.activeForeground" = "#${palette.text}";
      "editorIndentGuide.background1" = "#${palette.outlineSubtle}";
      "editorIndentGuide.activeBackground1" = "#${palette.outline}";
      "editorWhitespace.foreground" = "#${palette.outline}";
      "editorBracketMatch.background" = "#${palette.accent}26";
      "editorBracketMatch.border" = "#${palette.accent}";
      "editorGutter.background" = "#${palette.surface}";
      "editorGutter.addedBackground" = "#${palette.diffAdded}99";
      "editorGutter.deletedBackground" = "#${palette.diffRemoved}99";
      "editorGutter.commentRangeForeground" = "#${palette.info}";
      "editorError.foreground" = "#${palette.danger}";
      "editorWarning.foreground" = "#${palette.warning}";
      "editorInfo.foreground" = "#${palette.info}";
      "editorHint.foreground" = "#${palette.accent}";
      "list.activeSelectionBackground" = "#${palette.outline}";
      "list.activeSelectionForeground" = "#${palette.textStrong}";
      "list.inactiveSelectionBackground" = "#${palette.outlineSubtle}";
      "list.hoverBackground" = "#${palette.outline}";
      "list.hoverForeground" = "#${palette.textStrong}";
      "list.focusOutline" = "#${palette.accent}";
      "list.focusAndSelectionOutline" = "#${palette.accent}";
      "scrollbar.shadow" = "#${palette.surface}66";
      "scrollbarSlider.background" = "#${palette.scrollbar}66";
      "scrollbarSlider.hoverBackground" = "#${palette.muted}88";
      "scrollbarSlider.activeBackground" = "#${palette.accent}99";
      "editorOverviewRuler.addedForeground" = "#${palette.diffAdded}CC";
      "editorOverviewRuler.deletedForeground" = "#${palette.diffRemoved}CC";
      "editorOverviewRuler.commentForeground" = "#${palette.info}";
      "editorOverviewRuler.commentDraftForeground" = "#${palette.muted}";
      "editorOverviewRuler.commentUnresolvedForeground" = "#${palette.warning}";
      "minimapGutter.addedBackground" = "#${palette.diffAdded}99";
      "minimapGutter.deletedBackground" = "#${palette.diffRemoved}99";
      "diffEditor.insertedLineBackground" = "#${palette.diffAdded}26";
      "diffEditor.insertedTextBackground" = "#${palette.diffAdded}33";
      "diffEditor.removedLineBackground" = "#${palette.diffRemoved}26";
      "diffEditor.removedTextBackground" = "#${palette.diffRemoved}33";
      "diffEditor.border" = "#${palette.outlineSubtle}";
      "diffEditor.diagonalFill" = "#${palette.surfaceHover}";
      "statusBar.background" = "#${palette.surface}";
      "statusBar.foreground" = "#${palette.muted}";
      "statusBar.border" = "#${palette.surfaceHover}";
      "statusBar.debuggingBackground" = "#${palette.special}";
      "statusBar.debuggingForeground" = "#${palette.surface}";
      "statusBar.debuggingBorder" = "#${palette.special}";
      "statusBar.noFolderBackground" = "#${palette.surface}";
      "statusBar.noFolderForeground" = "#${palette.muted}";
      "statusBar.noFolderBorder" = "#${palette.surfaceHover}";
      "statusBar.focusBorder" = "#${palette.accent}";
      "statusBarItem.activeBackground" = "#${palette.surfaceHover}";
      "statusBarItem.hoverForeground" = "#${palette.textStrong}";
      "statusBarItem.hoverBackground" = "#${palette.surfaceHover}";
      "statusBarItem.compactHoverBackground" = "#${palette.surfaceHover}";
      "statusBarItem.focusBorder" = "#${palette.accent}";
      "statusBarItem.prominentBackground" = "#${palette.surfaceRaised}";
      "statusBarItem.prominentForeground" = "#${palette.muted}";
      "statusBarItem.prominentHoverBackground" = "#${palette.surfaceHover}";
      "statusBarItem.prominentHoverForeground" = "#${palette.textStrong}";
      "statusBarItem.remoteBackground" = "#${palette.surfaceRaised}";
      "statusBarItem.remoteForeground" = "#${palette.muted}";
      "statusBarItem.remoteHoverBackground" = "#${palette.surfaceHover}";
      "statusBarItem.remoteHoverForeground" = "#${palette.textStrong}";
      "statusBarItem.errorBackground" = "#${palette.danger}";
      "statusBarItem.errorForeground" = "#${palette.surface}";
      "statusBarItem.errorHoverBackground" = "#${palette.base0F}";
      "statusBarItem.errorHoverForeground" = "#${palette.surface}";
      "statusBarItem.warningBackground" = "#${palette.warning}";
      "statusBarItem.warningForeground" = "#${palette.surface}";
      "statusBarItem.warningHoverBackground" = "#${palette.cursor}";
      "statusBarItem.warningHoverForeground" = "#${palette.surface}";
      "statusBarItem.offlineBackground" = "#${palette.surfaceHover}";
      "statusBarItem.offlineForeground" = "#${palette.muted}";
      "statusBarItem.offlineHoverBackground" = "#${palette.scrollbar}";
      "statusBarItem.offlineHoverForeground" = "#${palette.textStrong}";
      "panel.background" = "#${palette.surface}";
      "panel.border" = "#${palette.outline}";
      "terminal.background" = "#${palette.surface}";
      "terminal.foreground" = "#${palette.text}";
      "terminalCursor.foreground" = "#${palette.cursor}";
      "terminal.ansiBlack" = "#${palette.outline}";
      "terminal.ansiRed" = "#${palette.danger}";
      "terminal.ansiGreen" = "#${palette.success}";
      "terminal.ansiYellow" = "#${palette.warning}";
      "terminal.ansiBlue" = "#${palette.syntaxFunction}";
      "terminal.ansiMagenta" = "#${palette.special}";
      "terminal.ansiCyan" = "#${palette.info}";
      "terminal.ansiWhite" = "#${palette.text}";
      "terminal.ansiBrightBlack" = "#${palette.muted}";
      "terminal.ansiBrightRed" = "#${palette.base0F}";
      "terminal.ansiBrightGreen" = "#${palette.success}";
      "terminal.ansiBrightYellow" = "#${palette.cursor}";
      "terminal.ansiBrightBlue" = "#${palette.accent}";
      "terminal.ansiBrightMagenta" = "#${palette.special}";
      "terminal.ansiBrightCyan" = "#${palette.info}";
      "terminal.ansiBrightWhite" = "#${palette.textStrong}";
      "terminal.findMatchBackground" = "#${palette.warning}40";
      "terminal.findMatchBorder" = "#${palette.warning}";
      "terminal.findMatchHighlightBackground" = "#${palette.warning}26";
      "ports.iconRunningProcessForeground" = "#${palette.accent}";
      "terminalCommandGuide.foreground" = "#${palette.muted}";
      "scmGraph.historyItemHoverDefaultLabelForeground" = "#${palette.surface}";
      "minimap.chatEditHighlight" = "#${palette.accent}66";
    };
    tokenColors = [
      {
        scope = [
          "comment"
          "punctuation.definition.comment"
        ];
        settings = {
          foreground = "#${palette.muted}";
          fontStyle = "italic";
        };
      }
      {
        scope = [
          "string"
          "string.quoted"
          "constant.other.symbol"
        ];
        settings = {
          foreground = "#${palette.success}";
        };
      }
      {
        scope = [
          "constant.numeric"
          "constant.language"
          "constant.character"
        ];
        settings = {
          foreground = "#${palette.base09}";
        };
      }
      {
        scope = [
          "keyword"
          "storage"
          "storage.type"
          "entity.name.tag"
        ];
        settings = {
          foreground = "#${palette.special}";
        };
      }
      {
        scope = [
          "entity.name.function"
          "support.function"
          "variable.function"
        ];
        settings = {
          foreground = "#${palette.syntaxFunction}";
        };
      }
      {
        scope = [
          "variable"
          "variable.parameter"
          "support.variable"
        ];
        settings = {
          foreground = "#${palette.text}";
        };
      }
      {
        scope = [
          "entity.name.type"
          "support.type"
          "entity.other.inherited-class"
          "entity.name.class"
          "entity.name.namespace"
        ];
        settings = {
          foreground = "#${palette.info}";
        };
      }
      {
        scope = [
          "entity.name.section"
          "markup.heading"
        ];
        settings = {
          foreground = "#${palette.warning}";
          fontStyle = "bold";
        };
      }
      {
        scope = [
          "invalid"
          "invalid.illegal"
        ];
        settings = {
          foreground = "#${palette.danger}";
        };
      }
      {
        scope = "keyword.operator";
        settings = {
          foreground = "#${palette.accent}";
        };
      }
      {
        scope = "string.regexp";
        settings = {
          foreground = "#${palette.base0F}";
        };
      }
      {
        scope = [
          "variable.other.property"
          "variable.object.property"
          "variable.other.object.property"
          "support.type.property-name"
          "entity.other.attribute-name"
          "entity.name.tag.yaml"
          "meta.object-literal.key"
          "meta.attribute.python"
        ];
        settings = {
          foreground = "#${palette.accent}";
        };
      }
      {
        scope = [
          "entity.name.function.decorator"
          "meta.decorator entity.name.function"
        ];
        settings = {
          foreground = "#${palette.warning}";
        };
      }
      {
        scope = "markup.inserted";
        settings = {
          foreground = "#${palette.diffAdded}";
        };
      }
      {
        scope = "markup.deleted";
        settings = {
          foreground = "#${palette.diffRemoved}";
        };
      }
      {
        scope = "markup.changed";
        settings = {
          foreground = "#${palette.warning}";
        };
      }
      {
        scope = "markup.bold";
        settings = {
          fontStyle = "bold";
        };
      }
      {
        scope = "markup.italic";
        settings = {
          fontStyle = "italic";
        };
      }
      {
        scope = [
          "markup.bold markup.italic"
          "markup.italic markup.bold"
        ];
        settings = {
          fontStyle = "bold italic";
        };
      }
      {
        scope = "markup.strikethrough";
        settings = {
          fontStyle = "strikethrough";
        };
      }
      {
        scope = "markup.inline.raw";
        settings = {
          foreground = "#${palette.success}";
        };
      }
      {
        scope = [
          "markup.underline.link"
          "string.other.link.title"
          "string.other.link.description"
        ];
        settings = {
          foreground = "#${palette.info}";
          fontStyle = "underline";
        };
      }
    ];
    semanticTokenColors = {
      namespace = "#${palette.info}";
      type = "#${palette.info}";
      class = "#${palette.info}";
      interface = "#${palette.info}";
      enum = "#${palette.info}";
      typeParameter = "#${palette.accent}";
      parameter = "#${palette.text}";
      variable = "#${palette.text}";
      property = "#${palette.accent}";
      enumMember = "#${palette.base09}";
      function = "#${palette.syntaxFunction}";
      method = "#${palette.syntaxFunction}";
      macro = "#${palette.special}";
      keyword = "#${palette.special}";
      string = "#${palette.success}";
      number = "#${palette.base09}";
      regexp = "#${palette.base0F}";
      operator = "#${palette.accent}";
      decorator = "#${palette.warning}";
      "*.deprecated" = {
        strikethrough = true;
      };
    };
  };
}
