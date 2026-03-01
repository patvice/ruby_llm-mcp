(function () {
  function normalizeUrl(base, path) {
    if (!base || !path) {
      return null;
    }
    var trimmedBase = base.replace(/\/+$/, "");
    var trimmedPath = path.replace(/^\/+/, "");
    return trimmedBase + "/" + trimmedPath;
  }

  function defaultMarkdownBase() {
    var repo = window.__rubyllmDocsRepoNwo || "";
    var branch = window.__rubyllmDocsSourceBranch || "main";

    if (!repo) {
      return "";
    }

    return "https://raw.githubusercontent.com/" + repo + "/" + branch + "/docs";
  }

  function resolveMarkdownBase(button) {
    var configuredBase = button.dataset.markdownBase || "";
    if (configuredBase) {
      return configuredBase;
    }

    var inferredBase = defaultMarkdownBase();
    if (inferredBase) {
      button.dataset.markdownBase = inferredBase;
    }
    return inferredBase;
  }

  function setButtonLabel(button, label) {
    button.textContent = label;
  }

  function restoreLabelAfterDelay(button, label, delay) {
    window.setTimeout(function () {
      if (!button.dataset || button.dataset.isBusy === "true") {
        return;
      }
      setButtonLabel(button, label);
    }, delay);
  }

  function copyText(text) {
    if (
      window.navigator &&
      window.navigator.clipboard &&
      window.navigator.clipboard.writeText
    ) {
      return window.navigator.clipboard.writeText(text);
    }

    return new Promise(function (resolve, reject) {
      var textarea = document.createElement("textarea");
      textarea.value = text;
      textarea.setAttribute("readonly", "");
      textarea.style.position = "fixed";
      textarea.style.left = "-9999px";
      document.body.appendChild(textarea);
      textarea.select();

      var ok = false;
      try {
        ok = document.execCommand("copy");
      } catch (error) {
        ok = false;
      } finally {
        document.body.removeChild(textarea);
      }

      if (ok) {
        resolve();
      } else {
        reject(new Error("Unable to copy."));
      }
    });
  }

  function getVisiblePageText() {
    var main = document.querySelector("#main-content > main");
    if (!main) {
      return "";
    }

    var clone = main.cloneNode(true);
    var selectorsToRemove = [
      ".page-actions",
      ".anchor-heading",
      "#markdown-toc",
      "#table-of-contents",
      "script",
      "style"
    ];

    selectorsToRemove.forEach(function (selector) {
      clone.querySelectorAll(selector).forEach(function (node) {
        node.remove();
      });
    });

    return (clone.textContent || "")
      .replace(/\u00a0/g, " ")
      .replace(/[ \t]+\n/g, "\n")
      .replace(/\n{3,}/g, "\n\n")
      .trim();
  }

  function fetchMarkdown(sourceUrl) {
    if (!sourceUrl) {
      return Promise.reject(new Error("Missing markdown source URL."));
    }

    return window.fetch(sourceUrl, { cache: "no-store" })
      .then(function (response) {
        if (!response.ok) {
          throw new Error("Failed to fetch markdown source.");
        }
        return response.text();
      })
      .then(function (markdown) {
        return stripFrontMatter(markdown);
      });
  }

  function stripFrontMatter(markdown) {
    var lines = markdown.split("\n");
    if (lines.length < 3 || lines[0].trim() !== "---") {
      return markdown;
    }

    var endIndex = -1;
    for (var i = 1; i < lines.length; i += 1) {
      if (lines[i].trim() === "---") {
        endIndex = i;
        break;
      }
    }

    if (endIndex === -1) {
      return markdown;
    }

    return lines.slice(endIndex + 1).join("\n").replace(/^\n+/, "");
  }

  function setupButton(button) {
    var base = resolveMarkdownBase(button);
    var path = button.dataset.markdownPath;
    var defaultLabel = button.dataset.labelDefault || "Copy page";
    var successLabel = button.dataset.labelSuccess || "Copied";
    var errorLabel = button.dataset.labelError || "Copy failed";

    setButtonLabel(button, defaultLabel);

    var sourceUrl = normalizeUrl(base, path);
    if (sourceUrl) {
      window.fetch(sourceUrl, { cache: "no-store" })
        .then(function (response) {
          if (!response.ok) {
            throw new Error("Failed to fetch markdown source.");
          }
          return response.text();
        })
        .then(function (markdown) {
          button.dataset.markdownSource = stripFrontMatter(markdown);
        })
        .catch(function () {
          button.dataset.markdownSource = "";
        });
    } else {
      button.dataset.markdownSource = "";
      button.title = "Missing markdown source configuration.";
    }

    button.addEventListener("click", function () {
      if (button.dataset.isBusy === "true") {
        return;
      }

      button.dataset.isBusy = "true";
      button.disabled = true;
      setButtonLabel(button, "Copying...");

      var cachedMarkdown = button.dataset.markdownSource || "";
      var copyPromise = cachedMarkdown
        ? copyText(cachedMarkdown)
        : fetchMarkdown(sourceUrl)
          .then(function (strippedMarkdown) {
            button.dataset.markdownSource = strippedMarkdown;
            return copyText(strippedMarkdown);
          })
          .catch(function () {
            var visibleText = getVisiblePageText();
            if (!visibleText) {
              throw new Error("Unable to load copy content.");
            }
            return copyText(visibleText);
          });

      copyPromise
        .then(function () {
          setButtonLabel(button, successLabel);
          button.title = "Copied to clipboard.";
          button.dataset.isBusy = "false";
          button.disabled = false;
          restoreLabelAfterDelay(button, defaultLabel, 2000);
        })
        .catch(function () {
          setButtonLabel(button, errorLabel);
          button.title = "Unable to copy markdown.";
          button.dataset.isBusy = "false";
          button.disabled = false;
          restoreLabelAfterDelay(button, defaultLabel, 2500);
        });
    });
  }

  function createButtonIfMissing() {
    if (document.querySelector(".js-copy-page-markdown")) {
      return;
    }

    var markdownPath = window.__rubyllmMcpMarkdownPath || "";
    if (!markdownPath || markdownPath.indexOf(".md") === -1) {
      return;
    }

    var main = document.querySelector("#main-content > main");
    if (!main) {
      return;
    }

    var actions = document.createElement("div");
    actions.className = "page-actions";

    var button = document.createElement("button");
    button.type = "button";
    button.className = "page-copy-button js-copy-page-markdown";
    button.dataset.markdownBase = window.__rubyllmMcpMarkdownSourceBaseUrl || "";
    button.dataset.markdownPath = markdownPath;
    button.dataset.labelDefault = "📋 Copy page";
    button.dataset.labelSuccess = "✅ Copied!";
    button.dataset.labelError = "⚠ Copy failed";
    button.innerHTML = '<span class="page-copy-button__text">Copy page</span>';

    actions.appendChild(button);
    main.insertBefore(actions, main.firstElementChild);
  }

  document.addEventListener("DOMContentLoaded", function () {
    createButtonIfMissing();

    var buttons = document.querySelectorAll(".js-copy-page-markdown");
    if (!buttons.length) {
      return;
    }

    buttons.forEach(function (button) {
      setupButton(button);
    });
  });
})();
