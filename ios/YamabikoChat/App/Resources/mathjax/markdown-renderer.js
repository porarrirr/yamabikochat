(function(global) {
  "use strict";
  var copyButtonLabel = window.__yamabikoCopyButtonLabel || "Copy";

  function escapeHtml(value) {
    return String(value || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function escapeAttr(value) {
    return escapeHtml(value).replace(/`/g, "&#96;");
  }

  function safeHref(rawUrl) {
    var url = String(rawUrl || "").trim();
    if (!url) return null;
    var unescaped = url.replace(/&amp;/g, "&");
    if (!/^https?:\/\//i.test(unescaped)) return null;
    return escapeAttr(unescaped);
  }

  function isEscaped(text, index) {
    var backslashCount = 0;
    var cursor = index - 1;
    while (cursor >= 0 && text.charAt(cursor) === "\\") {
      backslashCount += 1;
      cursor -= 1;
    }
    return backslashCount % 2 === 1;
  }

  function findClosingDelimiter(text, startIndex, openDelimiter, closeDelimiter) {
    var cursor = startIndex + openDelimiter.length;
    while (cursor < text.length) {
      if (
        text.slice(cursor, cursor + closeDelimiter.length) === closeDelimiter &&
        !isEscaped(text, cursor)
      ) {
        return cursor;
      }
      cursor += 1;
    }
    return -1;
  }

  function protectMathSegments(text) {
    var source = String(text || "");
    var tokens = [];
    var output = "";
    var i = 0;

    function pushToken(segment) {
      var key = "@@YBMATH" + tokens.length + "@@";
      tokens.push(segment);
      output += key;
    }

    while (i < source.length) {
      if (source.slice(i, i + 2) === "$$" && !isEscaped(source, i)) {
        var blockClose = findClosingDelimiter(source, i, "$$", "$$");
        if (blockClose > i + 1) {
          pushToken(source.slice(i, blockClose + 2));
          i = blockClose + 2;
          continue;
        }
      }

      if (source.slice(i, i + 2) === "\\[" && !isEscaped(source, i)) {
        var bracketClose = findClosingDelimiter(source, i, "\\[", "\\]");
        if (bracketClose !== -1) {
          pushToken(source.slice(i, bracketClose + 2));
          i = bracketClose + 2;
          continue;
        }
      }

      if (source.slice(i, i + 2) === "\\(" && !isEscaped(source, i)) {
        var parenClose = findClosingDelimiter(source, i, "\\(", "\\)");
        if (parenClose !== -1) {
          pushToken(source.slice(i, parenClose + 2));
          i = parenClose + 2;
          continue;
        }
      }

      if (source.charAt(i) === "$" && !isEscaped(source, i) && source.charAt(i + 1) !== "$") {
        var inlineClose = i + 1;
        while (inlineClose < source.length) {
          if (
            source.charAt(inlineClose) === "$" &&
            !isEscaped(source, inlineClose) &&
            source.charAt(inlineClose - 1) !== "$" &&
            source.charAt(inlineClose + 1) !== "$"
          ) {
            break;
          }
          inlineClose += 1;
        }

        if (inlineClose < source.length && inlineClose > i + 1) {
          pushToken(source.slice(i, inlineClose + 1));
          i = inlineClose + 1;
          continue;
        }
      }

      output += source.charAt(i);
      i += 1;
    }

    return { text: output, tokens: tokens };
  }

  function applyInlineMarkdown(text) {
    var mathProtected = protectMathSegments(text);
    var input = mathProtected.text;
    if (!input) return "";

    var inlineBreakTokens = [];
    input = input.replace(/<br\s*\/?>/gi, function() {
      var key = "@@YBBR" + inlineBreakTokens.length + "@@";
      inlineBreakTokens.push("<br/>");
      return key;
    });

    var inlineCodeTokens = [];
    input = input.replace(/`([^`]+?)`/g, function(_, code) {
      var key = "@@YBCODE" + inlineCodeTokens.length + "@@";
      inlineCodeTokens.push("<code>" + escapeHtml(code) + "</code>");
      return key;
    });

    var inlineLinkTokens = [];
    input = input.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, href) {
      var safe = safeHref(href);
      var textLabel = escapeHtml(label || href);
      var key = "@@YBLINK" + inlineLinkTokens.length + "@@";
      if (!safe) {
        inlineLinkTokens.push(textLabel);
      } else {
        inlineLinkTokens.push('<a href="' + safe + '">' + textLabel + "</a>");
      }
      return key;
    });

    var output = escapeHtml(input);

    output = output.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
    output = output.replace(/__([^_]+)__/g, "<strong>$1</strong>");
    output = output.replace(/\*([^*\n]+)\*/g, "<em>$1</em>");
    output = output.replace(/_([^_\n]+)_/g, "<em>$1</em>");

    output = output.replace(/@@YBLINK(\d+)@@/g, function(_, index) {
      return inlineLinkTokens[Number(index)] || "";
    });

    output = output.replace(/@@YBCODE(\d+)@@/g, function(_, index) {
      return inlineCodeTokens[Number(index)] || "";
    });

    output = output.replace(/@@YBBR(\d+)@@/g, function(_, index) {
      return inlineBreakTokens[Number(index)] || "";
    });

    output = output.replace(/@@YBMATH(\d+)@@/g, function(_, index) {
      return escapeHtml(mathProtected.tokens[Number(index)] || "");
    });

    return output;
  }

  function isBlank(line) {
    return !line || !line.trim();
  }

  function renderParagraph(lines) {
    var content = lines.join(" ").trim();
    if (!content) return "";
    return "<p>" + applyInlineMarkdown(content) + "</p>";
  }

  function parseList(lines, startIndex, ordered) {
    var index = startIndex;
    var items = [];
    var pattern = ordered ? /^\s*\d+\.\s+(.*)$/ : /^\s*[-*+]\s+(.*)$/;

    while (index < lines.length) {
      var line = lines[index];
      var match = line.match(pattern);
      if (!match) break;
      items.push("<li>" + applyInlineMarkdown(match[1].trim()) + "</li>");
      index += 1;
    }

    var tag = ordered ? "ol" : "ul";
    return {
      html: "<" + tag + ">" + items.join("") + "</" + tag + ">",
      nextIndex: index
    };
  }

  function parseBlockquote(lines, startIndex) {
    var index = startIndex;
    var quoteLines = [];

    while (index < lines.length) {
      var line = lines[index];
      if (!/^\s*>/.test(line)) break;
      quoteLines.push(line.replace(/^\s*>\s?/, ""));
      index += 1;
    }

    return {
      html: "<blockquote>" + renderBlocks(quoteLines.join("\n")) + "</blockquote>",
      nextIndex: index
    };
  }

  function hasUnescapedPipe(text) {
    var value = String(text || "");
    for (var i = 0; i < value.length; i += 1) {
      if (value.charAt(i) === "|" && !isEscaped(value, i)) {
        return true;
      }
    }
    return false;
  }

  function splitTableRow(line) {
    var text = String(line || "").trim();
    if (!text) return [];
    if (text.charAt(0) === "|") text = text.slice(1);
    if (text.charAt(text.length - 1) === "|") text = text.slice(0, -1);

    var cells = [];
    var segmentStart = 0;
    for (var i = 0; i < text.length; i += 1) {
      if (text.charAt(i) === "|" && !isEscaped(text, i)) {
        cells.push(text.slice(segmentStart, i));
        segmentStart = i + 1;
      }
    }
    cells.push(text.slice(segmentStart));

    return cells.map(function(cell) {
      return cell.replace(/\\\|/g, "|").trim();
    });
  }

  function isDelimiterCell(cell) {
    var value = String(cell || "").trim();
    return /^:?-{3,}:?$/.test(value);
  }

  function parseAlignment(cell) {
    var value = String(cell || "").trim();
    if (/^:-{3,}:$/.test(value)) return "center";
    if (/^:-{3,}$/.test(value)) return "left";
    if (/^-{3,}:$/.test(value)) return "right";
    return null;
  }

  function normalizeCells(cells, columnCount) {
    var normalized = [];
    for (var i = 0; i < columnCount; i += 1) {
      normalized.push(String((cells && cells[i]) || "").trim());
    }
    return normalized;
  }

  function renderTableCell(tag, text, alignment) {
    var style = alignment ? ' style="text-align: ' + alignment + ';"' : "";
    return "<" + tag + style + ">" + applyInlineMarkdown(text) + "</" + tag + ">";
  }

  function parseTable(lines, startIndex) {
    if (startIndex + 1 >= lines.length) return null;

    var headerLine = lines[startIndex];
    var delimiterLine = lines[startIndex + 1];
    if (!hasUnescapedPipe(headerLine) || !hasUnescapedPipe(delimiterLine)) return null;

    var headerCells = splitTableRow(headerLine);
    var delimiterCells = splitTableRow(delimiterLine);
    if (!headerCells.length || delimiterCells.length < headerCells.length) return null;
    if (!delimiterCells.slice(0, headerCells.length).every(isDelimiterCell)) return null;

    var columnCount = headerCells.length;
    var alignments = delimiterCells.slice(0, columnCount).map(parseAlignment);
    var normalizedHeader = normalizeCells(headerCells, columnCount);

    var rowHtml = normalizedHeader.map(function(cell, index) {
      return renderTableCell("th", cell, alignments[index]);
    }).join("");

    var rows = [];
    var index = startIndex + 2;
    while (index < lines.length) {
      var line = lines[index];
      if (isBlank(line) || !hasUnescapedPipe(line)) break;
      var cells = splitTableRow(line);
      if (!cells.length) break;
      var normalizedCells = normalizeCells(cells, columnCount);
      rows.push("<tr>" + normalizedCells.map(function(cell, cellIndex) {
        return renderTableCell("td", cell, alignments[cellIndex]);
      }).join("") + "</tr>");
      index += 1;
    }

    return {
      html:
        "<div class=\"yamabiko-table-wrap\">" +
          "<table>" +
            "<thead><tr>" + rowHtml + "</tr></thead>" +
            "<tbody>" + rows.join("") + "</tbody>" +
          "</table>" +
        "</div>",
      nextIndex: index
    };
  }

  function renderBlocks(input) {
    var source = String(input || "").replace(/\r\n?/g, "\n");
    var codeBlocks = [];

    source = source.replace(/```([^\n`]*)\n([\s\S]*?)```/g, function(_, language, code) {
      var key = "@@CODE_BLOCK_" + codeBlocks.length + "@@";
      var langClass = String(language || "").trim();
      var classAttr = langClass ? ' class="language-' + escapeAttr(langClass) + '"' : "";
      codeBlocks.push(
        "<div class=\"yamabiko-code-block\">" +
          "<button type=\"button\" class=\"yamabiko-copy-button\">" + copyButtonLabel + "</button>" +
          "<pre><code" + classAttr + ">" + escapeHtml(code) + "</code></pre>" +
        "</div>"
      );
      return key;
    });

    var lines = source.split("\n");
    var htmlParts = [];
    var paragraphBuffer = [];

    function flushParagraph() {
      if (!paragraphBuffer.length) return;
      var paragraph = renderParagraph(paragraphBuffer);
      if (paragraph) htmlParts.push(paragraph);
      paragraphBuffer = [];
    }

    var i = 0;
    while (i < lines.length) {
      var line = lines[i];
      var trimmed = line.trim();

      if (isBlank(line)) {
        flushParagraph();
        i += 1;
        continue;
      }

      if (/^@@CODE_BLOCK_\d+@@$/.test(trimmed)) {
        flushParagraph();
        var codeIndex = Number(trimmed.replace(/\D/g, ""));
        htmlParts.push(codeBlocks[codeIndex] || "");
        i += 1;
        continue;
      }

      var heading = line.match(/^(#{1,6})\s+(.*)$/);
      if (heading) {
        flushParagraph();
        var level = heading[1].length;
        htmlParts.push("<h" + level + ">" + applyInlineMarkdown(heading[2].trim()) + "</h" + level + ">");
        i += 1;
        continue;
      }

      if (/^\s*([-*_])\1{2,}\s*$/.test(line)) {
        flushParagraph();
        htmlParts.push("<hr/>");
        i += 1;
        continue;
      }

      if (/^\s*>/.test(line)) {
        flushParagraph();
        var quote = parseBlockquote(lines, i);
        htmlParts.push(quote.html);
        i = quote.nextIndex;
        continue;
      }

      var parsedTable = parseTable(lines, i);
      if (parsedTable) {
        flushParagraph();
        htmlParts.push(parsedTable.html);
        i = parsedTable.nextIndex;
        continue;
      }

      if (/^\s*[-*+]\s+/.test(line)) {
        flushParagraph();
        var unordered = parseList(lines, i, false);
        htmlParts.push(unordered.html);
        i = unordered.nextIndex;
        continue;
      }

      if (/^\s*\d+\.\s+/.test(line)) {
        flushParagraph();
        var ordered = parseList(lines, i, true);
        htmlParts.push(ordered.html);
        i = ordered.nextIndex;
        continue;
      }

      paragraphBuffer.push(line.trim());
      i += 1;
    }

    flushParagraph();

    return htmlParts.join("\n");
  }

  global.yamabikoRenderMarkdown = function(markdown) {
    return renderBlocks(markdown);
  };
})(window);
