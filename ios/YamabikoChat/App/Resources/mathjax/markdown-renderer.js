(function(global) {
  "use strict";

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

  function applyInlineMarkdown(text) {
    var input = String(text || "");
    if (!input) return "";

    var inlineCodeTokens = [];
    input = input.replace(/`([^`]+?)`/g, function(_, code) {
      var key = "@@INLINE_CODE_" + inlineCodeTokens.length + "@@";
      inlineCodeTokens.push("<code>" + escapeHtml(code) + "</code>");
      return key;
    });

    var inlineLinkTokens = [];
    input = input.replace(/\[([^\]]+)\]\(([^)]+)\)/g, function(_, label, href) {
      var safe = safeHref(href);
      var textLabel = escapeHtml(label || href);
      var key = "@@INLINE_LINK_" + inlineLinkTokens.length + "@@";
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

    output = output.replace(/@@INLINE_LINK_(\d+)@@/g, function(_, index) {
      return inlineLinkTokens[Number(index)] || "";
    });

    output = output.replace(/@@INLINE_CODE_(\d+)@@/g, function(_, index) {
      return inlineCodeTokens[Number(index)] || "";
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

  function renderBlocks(input) {
    var source = String(input || "").replace(/\r\n?/g, "\n");
    var codeBlocks = [];

    source = source.replace(/```([^\n`]*)\n([\s\S]*?)```/g, function(_, language, code) {
      var key = "@@CODE_BLOCK_" + codeBlocks.length + "@@";
      var langClass = String(language || "").trim();
      var classAttr = langClass ? ' class="language-' + escapeAttr(langClass) + '"' : "";
      codeBlocks.push("<pre><code" + classAttr + ">" + escapeHtml(code) + "</code></pre>");
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
