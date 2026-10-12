import Foundation

struct GenUITool: LocalToolExecutor {
    static let name = "genui"
    static let definition = ToolDefinition(
        name: name,
        description: "Create a persisted interactive GenUI document. Choose exactly one renderer: legacy components with numeric inputs and =arithmetic formulas (+ - * / ^, parentheses, min, max, abs, round, pow, payment(principal,annualPercent,years); annualPercent=5 means 5%), a declarative ui node tree, or a code JavaScript function body returning DIL.h nodes. Component names and properties are case sensitive. Declarative bind names a state key; {{key}} interpolates state, and onChange setState actions use value \"$value\" for the changed value. Events take {type:\"setState\",key:\"count\",value:1}, resetState, copy(text), openUrl(url), issueNewTurn(query), or openEntityDetail(args) action objects. Host actions require a user gesture; AI follow-ups use the normal Pi conversation path. JavaScript supports DIL.useState/useMemo/useEffect/useCallback/useRef/useId/useTheme/useBreakpoint. Example code: const [count,setCount]=DIL.useState(0); return DIL.h(\"button\",{onClick:()=>setCount(count+1)},String(count)); Resources are explicit keyed title/url/src/text/mime objects. Use only supplied HTTPS URLs; missing refs display unavailable. Native maps use explicitly supplied coordinates and Apple MapKit directions; route stop optimization is unavailable. There is no proprietary ChatGPT data, search or backend API. SVG primitives require an svg ancestor; references use local fragment IDs. AppBlock.content or entrypoint can contain an inline node tree. Maximum 256 KiB document, 64 KiB code, 512 nodes and 32 levels. Supported component properties: {\"text\":[\"bind\",\"color\",\"highlight\",\"inline\",\"italic\",\"key\",\"lineThrough\",\"maxLines\",\"minLines\",\"preserveWhitespace\",\"x\",\"y\",\"dx\",\"dy\",\"textAnchor\",\"dominantBaseline\",\"fill\",\"stroke\",\"fontSize\",\"transform\",\"size\",\"strong\",\"tabularNums\",\"textAlign\",\"truncate\",\"underline\",\"weight\",\"width\"],\"title\":[\"bind\",\"color\",\"italic\",\"key\",\"maxLines\",\"size\",\"strong\",\"tabularNums\",\"textAlign\",\"truncate\",\"weight\",\"width\"],\"caption\":[\"bind\",\"color\",\"key\",\"maxLines\",\"textAlign\",\"truncate\",\"weight\"],\"label\":[\"bind\",\"color\",\"htmlFor\",\"key\",\"size\",\"textAlign\",\"truncate\",\"weight\",\"width\"],\"badge\":[\"bind\",\"color\",\"key\",\"label\",\"maxWidth\",\"onHover\",\"padding\",\"pill\",\"size\",\"variant\",\"weight\"],\"bold\":[\"bind\",\"key\",\"weight\"],\"italic\":[\"bind\",\"key\"],\"underline\":[\"bind\",\"key\"],\"strikethrough\":[\"bind\",\"key\"],\"code\":[\"bind\",\"key\"],\"math\":[\"bind\",\"block\",\"key\",\"value\"],\"box\":[\"align\",\"aspectRatio\",\"background\",\"bind\",\"border\",\"clip\",\"columnGap\",\"direction\",\"disableAutoSpacing\",\"flex\",\"flush\",\"gap\",\"height\",\"justify\",\"key\",\"maxHeight\",\"maxSize\",\"maxWidth\",\"minHeight\",\"minSize\",\"minWidth\",\"padding\",\"radius\",\"role\",\"rowGap\",\"scrollable\",\"size\",\"theme\",\"width\",\"wrap\"],\"row\":[\"align\",\"aspectRatio\",\"background\",\"bind\",\"border\",\"clip\",\"direction\",\"disableAutoSpacing\",\"flex\",\"flush\",\"gap\",\"height\",\"justify\",\"key\",\"maxHeight\",\"maxSize\",\"maxWidth\",\"minHeight\",\"minSize\",\"minWidth\",\"padding\",\"radius\",\"role\",\"rowGap\",\"scrollable\",\"size\",\"theme\",\"width\",\"wrap\"],\"col\":[\"align\",\"aspectRatio\",\"background\",\"bind\",\"border\",\"clip\",\"columnGap\",\"direction\",\"disableAutoSpacing\",\"flex\",\"flush\",\"gap\",\"height\",\"justify\",\"key\",\"maxHeight\",\"maxSize\",\"maxWidth\",\"minHeight\",\"minSize\",\"minWidth\",\"padding\",\"radius\",\"role\",\"scrollable\",\"size\",\"theme\",\"width\",\"wrap\"],\"grid\":[\"bind\",\"columnGap\",\"columns\",\"gap\",\"key\",\"minChildWidth\",\"rowGap\",\"rows\"],\"grid-item\":[\"bind\",\"key\",\"rowSpan\",\"span\"],\"flow\":[\"bind\",\"columns\",\"gap\",\"key\",\"layout\",\"rows\"],\"flow-item\":[\"align\",\"aspectMode\",\"aspectRatio\",\"background\",\"bind\",\"border\",\"clip\",\"direction\",\"disableAutoSpacing\",\"flex\",\"flush\",\"gap\",\"height\",\"justify\",\"key\",\"maxHeight\",\"maxWidth\",\"minHeight\",\"minWidth\",\"padding\",\"radius\",\"role\",\"rowSpan\",\"scrollable\",\"span\",\"theme\",\"width\",\"wrap\"],\"card\":[\"background\",\"bind\",\"disableAutoSpacing\",\"gap\",\"height\",\"justify\",\"key\",\"padding\",\"shadow\",\"size\",\"theme\",\"variant\",\"width\"],\"divider\":[\"bind\",\"color\",\"flush\",\"key\",\"size\",\"spacing\"],\"spacer\":[\"bind\",\"key\",\"minSize\"],\"blockquote\":[\"bind\",\"key\"],\"button\":[\"bind\",\"block\",\"color\",\"disabled\",\"key\",\"label\",\"loading\",\"onClick\",\"pill\",\"size\",\"submit\",\"uniform\",\"variant\"],\"input\":[\"autoSelect\",\"bind\",\"defaultValue\",\"disabled\",\"fontSize\",\"inputType\",\"invalid\",\"key\",\"mask\",\"name\",\"onChange\",\"pill\",\"placeholder\",\"required\",\"size\",\"value\",\"variant\"],\"textarea\":[\"autoResize\",\"autoSelect\",\"bind\",\"defaultValue\",\"disabled\",\"invalid\",\"key\",\"maxRows\",\"name\",\"onChange\",\"placeholder\",\"required\",\"rows\",\"size\",\"value\",\"variant\"],\"slider\":[\"bind\",\"defaultValue\",\"disabled\",\"key\",\"marks\",\"max\",\"min\",\"name\",\"onChange\",\"required\",\"sliderStyle\",\"step\",\"value\"],\"checkbox\":[\"bind\",\"checked\",\"defaultChecked\",\"disabled\",\"key\",\"label\",\"lineThrough\",\"name\",\"onChange\",\"required\",\"shape\",\"value\"],\"select\":[\"align\",\"bind\",\"block\",\"clearable\",\"defaultValue\",\"disabled\",\"icon\",\"key\",\"name\",\"onChange\",\"options\",\"pill\",\"placeholder\",\"required\",\"side\",\"size\",\"value\",\"variant\"],\"segmented-control\":[\"bind\",\"defaultValue\",\"disabled\",\"key\",\"label\",\"onChange\",\"options\",\"pill\",\"size\",\"value\",\"variant\"],\"radio-group\":[\"bind\",\"defaultValue\",\"direction\",\"disabled\",\"key\",\"label\",\"name\",\"onChange\",\"required\",\"value\"],\"radio\":[\"bind\",\"disabled\",\"id\",\"key\",\"required\",\"value\"],\"date-picker\":[\"align\",\"bind\",\"block\",\"clearable\",\"defaultValue\",\"disabled\",\"key\",\"max\",\"min\",\"onChange\",\"pill\",\"placeholder\",\"required\",\"side\",\"size\",\"value\",\"variant\"],\"form\":[\"align\",\"background\",\"bind\",\"border\",\"clip\",\"direction\",\"disableAutoSpacing\",\"flex\",\"flush\",\"gap\",\"height\",\"justify\",\"key\",\"maxHeight\",\"maxWidth\",\"minHeight\",\"minWidth\",\"onSubmit\",\"padding\",\"radius\",\"role\",\"scrollable\",\"theme\",\"width\",\"wrap\"],\"pressable\":[\"align\",\"aspectRatio\",\"background\",\"bind\",\"border\",\"clip\",\"direction\",\"disableAutoSpacing\",\"disabled\",\"flex\",\"flush\",\"gap\",\"height\",\"inline\",\"justify\",\"key\",\"maxHeight\",\"maxSize\",\"maxWidth\",\"minHeight\",\"minSize\",\"minWidth\",\"onClick\",\"padding\",\"radius\",\"role\",\"scrollable\",\"size\",\"theme\",\"tooltip\",\"width\",\"wrap\"],\"table\":[\"bind\",\"columnSizing\",\"dividers\",\"emptyLabel\",\"key\",\"stickyHeader\"],\"table-section\":[\"bind\",\"header\",\"key\",\"rowDivider\"],\"table-row\":[\"bind\",\"header\",\"key\",\"label\",\"labelColSpan\"],\"table-cell\":[\"align\",\"bind\",\"colSpan\",\"header\",\"key\",\"padding\",\"rowSpan\",\"vAlign\",\"width\"],\"list\":[\"bind\",\"connector\",\"gap\",\"key\",\"marker\",\"maxMarkerSize\",\"start\"],\"list-item\":[\"bind\",\"description\",\"disabled\",\"key\",\"label\",\"marker\",\"markerSize\"],\"carousel\":[\"activeIndex\",\"bind\",\"flush\",\"gap\",\"key\",\"onChange\",\"showArrows\",\"snap\",\"snapAlign\",\"visibleItems\"],\"carousel-item\":[\"aspectRatio\",\"background\",\"bind\",\"border\",\"gap\",\"height\",\"key\",\"maxHeight\",\"maxWidth\",\"minHeight\",\"minWidth\",\"padding\",\"radius\",\"variant\",\"width\"],\"carousel-media-item\":[\"aspectRatio\",\"background\",\"bind\",\"border\",\"gap\",\"height\",\"key\",\"maxHeight\",\"maxWidth\",\"media\",\"minHeight\",\"minWidth\",\"padding\",\"radius\",\"size\",\"variant\",\"width\"],\"popover\":[\"bind\",\"hoverOpenDelay\",\"key\",\"open\",\"showOnHover\"],\"popover-trigger\":[\"bind\",\"block\",\"key\",\"onClick\"],\"popover-content\":[\"align\",\"bind\",\"key\",\"showCloseButton\",\"side\",\"sideOffset\"],\"AsyncImage\":[\"alt\",\"aspectRatio\",\"bind\",\"fallback\",\"fit\",\"frame\",\"group\",\"height\",\"key\",\"maxHeight\",\"maxWidth\",\"minHeight\",\"minWidth\",\"query\",\"radius\",\"ref\",\"src\",\"width\"],\"AsyncImageGroup\":[\"aspectRatio\",\"bind\",\"fallback\",\"key\",\"layout\",\"numPerQuery\",\"query\",\"ref\",\"refs\",\"size\"],\"AsyncVideo\":[\"bind\",\"key\",\"ref\"],\"Chart\":[\"bind\",\"content\",\"key\"],\"MapWidgetV2\":[\"answer\",\"arrive_by\",\"bind\",\"carousel\",\"depart_at\",\"fill\",\"groups\",\"groups_title\",\"key\",\"minHeight\",\"narrative\",\"optimize_stop_order\",\"origin\",\"points\",\"show_route\",\"title\",\"travel_mode\"],\"icon\":[\"bind\",\"color\",\"inline\",\"key\",\"name\",\"size\"],\"favicon\":[\"alt\",\"bind\",\"frame\",\"inline\",\"key\",\"size\",\"url\"],\"svg\":[\"bind\",\"color\",\"fill\",\"height\",\"key\",\"preserveAspectRatio\",\"size\",\"stroke\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeWidth\",\"viewBox\",\"width\",\"xmlns\"],\"Link\":[\"bind\",\"key\",\"ref\",\"title\",\"url\"],\"Entity\":[\"address\",\"bind\",\"category\",\"disambig\",\"key\",\"location\",\"query\",\"ref\",\"value\"],\"Cite\":[\"bind\",\"key\",\"params\",\"ref\",\"refs\"],\"FileCite\":[\"bind\",\"key\",\"line_range_end\",\"line_range_start\",\"ref\"],\"CodeCite\":[\"bind\",\"citation_id\",\"key\",\"line_range_end\",\"line_range_start\",\"tool\"],\"FileNavList\":[\"bind\",\"items\",\"key\"],\"FollowUp\":[\"bind\",\"key\",\"query\",\"source\",\"value\"],\"MemoryCite\":[\"bind\",\"key\"],\"AppBlock\":[\"app_block_id\",\"bind\",\"bundle_version\",\"content\",\"entrypoint\",\"icon\",\"key\",\"language\",\"title\",\"variant\"],\"CodeBlock\":[\"bind\",\"editable\",\"interactive\",\"key\",\"language\",\"model_previewable\"],\"WritingBlock\":[\"bind\",\"id\",\"key\",\"options\",\"subject\",\"variant\"],\"g\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"path\":[\"clipPath\",\"d\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"pathLength\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"circle\":[\"clipPath\",\"cx\",\"cy\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"r\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"ellipse\":[\"clipPath\",\"cx\",\"cy\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"rx\",\"ry\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"rect\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"height\",\"id\",\"key\",\"opacity\",\"rx\",\"ry\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\",\"width\",\"x\",\"y\"],\"line\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\",\"x1\",\"x2\",\"y1\",\"y2\"],\"polyline\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"points\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"polygon\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"points\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"defs\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"linearGradient\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"gradientTransform\",\"gradientUnits\",\"id\",\"key\",\"opacity\",\"spreadMethod\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\",\"x1\",\"x2\",\"y1\",\"y2\"],\"radialGradient\":[\"clipPath\",\"cx\",\"cy\",\"fill\",\"fillOpacity\",\"fillRule\",\"fr\",\"fx\",\"fy\",\"gradientTransform\",\"gradientUnits\",\"id\",\"key\",\"opacity\",\"r\",\"spreadMethod\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"stop\":[\"clipPath\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"offset\",\"opacity\",\"stopColor\",\"stopOpacity\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"],\"clipPath\":[\"clipPath\",\"clipPathUnits\",\"fill\",\"fillOpacity\",\"fillRule\",\"id\",\"key\",\"opacity\",\"stroke\",\"strokeDasharray\",\"strokeDashoffset\",\"strokeLinecap\",\"strokeLinejoin\",\"strokeOpacity\",\"strokeWidth\",\"transform\"]}",
        parametersJSON: #"""
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "title": {
              "type": "string",
              "maxLength": 4096
            },
            "subtitle": {
              "type": "string"
            },
            "inputs": {
              "type": "array",
              "maxItems": 24,
              "items": {
                "type": "object",
                "properties": {
                  "id": {
                    "type": "string",
                    "pattern": "^[A-Za-z_][A-Za-z0-9_]{0,63}$"
                  },
                  "label": {
                    "type": "string"
                  },
                  "kind": {
                    "type": "string",
                    "enum": [
                      "slider",
                      "number",
                      "select",
                      "text",
                      "toggle"
                    ]
                  },
                  "value": {
                    "type": "number",
                    "description": "Numeric default; defaults to 0. Toggle uses 0 or 1."
                  },
                  "text": {
                    "type": "string",
                    "description": "Text default; defaults to empty."
                  },
                  "min": {
                    "type": "number"
                  },
                  "max": {
                    "type": "number"
                  },
                  "step": {
                    "type": "number",
                    "exclusiveMinimum": 0
                  },
                  "unit": {
                    "type": "string"
                  },
                  "options": {
                    "type": "array",
                    "maxItems": 32,
                    "items": {
                      "type": "object",
                      "properties": {
                        "label": {
                          "type": "string"
                        },
                        "value": {
                          "type": "number"
                        }
                      },
                      "required": [
                        "label",
                        "value"
                      ]
                    }
                  }
                },
                "required": [
                  "id",
                  "label",
                  "kind"
                ]
              }
            },
            "components": {
              "type": "array",
              "minItems": 1,
              "maxItems": 48,
              "items": {
                "type": "object",
                "properties": {
                  "id": {
                    "type": "string"
                  },
                  "kind": {
                    "type": "string",
                    "enum": [
                      "text",
                      "metric",
                      "table",
                      "chart",
                      "cards"
                    ]
                  },
                  "title": {
                    "type": "string"
                  },
                  "text": {
                    "type": "string",
                    "description": "Required for text."
                  },
                  "value": {
                    "type": "string",
                    "description": "Required for metric; literal or =formula."
                  },
                  "format": {
                    "type": "string",
                    "enum": [
                      "number",
                      "currency",
                      "percent"
                    ]
                  },
                  "unit": {
                    "type": "string"
                  },
                  "columns": {
                    "type": "array",
                    "maxItems": 12,
                    "items": {
                      "type": "string"
                    }
                  },
                  "rows": {
                    "type": "array",
                    "maxItems": 100,
                    "items": {
                      "type": "array",
                      "items": {
                        "type": "string"
                      }
                    }
                  },
                  "series": {
                    "type": "array",
                    "maxItems": 8,
                    "items": {
                      "type": "object",
                      "properties": {
                        "name": {
                          "type": "string"
                        },
                        "points": {
                          "type": "array",
                          "maxItems": 100,
                          "items": {
                            "type": "object",
                            "properties": {
                              "label": {
                                "type": "string"
                              },
                              "value": {
                                "type": "string",
                                "description": "Numeric literal or =formula."
                              }
                            },
                            "required": [
                              "label",
                              "value"
                            ]
                          }
                        }
                      },
                      "required": [
                        "name",
                        "points"
                      ]
                    }
                  },
                  "items": {
                    "type": "array",
                    "maxItems": 24,
                    "items": {
                      "type": "object",
                      "properties": {
                        "title": {
                          "type": "string"
                        },
                        "value": {
                          "type": "string"
                        },
                        "detail": {
                          "type": "string"
                        }
                      },
                      "required": [
                        "title",
                        "value"
                      ]
                    }
                  }
                },
                "required": [
                  "id",
                  "kind"
                ]
              }
            },
            "ui": {
              "$ref": "#/$defs/node"
            },
            "code": {
              "type": "string",
              "maxLength": 65536,
              "description": "JavaScript function body returning DIL.h(type,props,...children). Client-side only; DIL hooks are available."
            },
            "state": {
              "type": "object",
              "maxProperties": 64
            },
            "resources": {
              "type": "object",
              "maxProperties": 64,
              "additionalProperties": {
                "type": "object",
                "additionalProperties": false,
                "properties": {
                  "title": {
                    "type": "string"
                  },
                  "url": {
                    "type": "string"
                  },
                  "src": {
                    "type": "string"
                  },
                  "text": {
                    "type": "string"
                  },
                  "mime": {
                    "type": "string"
                  }
                }
              }
            }
          },
          "required": [
            "title"
          ],
          "oneOf": [
            {
              "required": [
                "components"
              ],
              "not": {
                "anyOf": [
                  {
                    "required": [
                      "ui"
                    ]
                  },
                  {
                    "required": [
                      "code"
                    ]
                  }
                ]
              }
            },
            {
              "required": [
                "ui"
              ],
              "not": {
                "anyOf": [
                  {
                    "required": [
                      "components"
                    ]
                  },
                  {
                    "required": [
                      "code"
                    ]
                  }
                ]
              }
            },
            {
              "required": [
                "code"
              ],
              "not": {
                "anyOf": [
                  {
                    "required": [
                      "components"
                    ]
                  },
                  {
                    "required": [
                      "ui"
                    ]
                  }
                ]
              }
            }
          ],
          "$defs": {
            "node": {
              "type": "object",
              "additionalProperties": false,
              "properties": {
                "type": {
                  "type": "string",
                  "enum": [
                    "text",
                    "title",
                    "caption",
                    "label",
                    "badge",
                    "bold",
                    "italic",
                    "underline",
                    "strikethrough",
                    "code",
                    "math",
                    "box",
                    "row",
                    "col",
                    "grid",
                    "grid-item",
                    "flow",
                    "flow-item",
                    "card",
                    "divider",
                    "spacer",
                    "blockquote",
                    "button",
                    "input",
                    "textarea",
                    "slider",
                    "checkbox",
                    "select",
                    "segmented-control",
                    "radio-group",
                    "radio",
                    "date-picker",
                    "form",
                    "pressable",
                    "table",
                    "table-section",
                    "table-row",
                    "table-cell",
                    "list",
                    "list-item",
                    "carousel",
                    "carousel-item",
                    "carousel-media-item",
                    "popover",
                    "popover-trigger",
                    "popover-content",
                    "AsyncImage",
                    "AsyncImageGroup",
                    "AsyncVideo",
                    "Chart",
                    "MapWidgetV2",
                    "icon",
                    "favicon",
                    "svg",
                    "Link",
                    "Entity",
                    "Cite",
                    "FileCite",
                    "CodeCite",
                    "FileNavList",
                    "FollowUp",
                    "MemoryCite",
                    "AppBlock",
                    "CodeBlock",
                    "WritingBlock",
                    "g",
                    "path",
                    "circle",
                    "ellipse",
                    "rect",
                    "line",
                    "polyline",
                    "polygon",
                    "defs",
                    "linearGradient",
                    "radialGradient",
                    "stop",
                    "clipPath"
                  ]
                },
                "props": {
                  "type": "object"
                },
                "children": {
                  "type": "array",
                  "maxItems": 512,
                  "items": {
                    "$ref": "#/$defs/child"
                  }
                }
              },
              "required": [
                "type"
              ]
            },
            "child": {
              "anyOf": [
                {
                  "$ref": "#/$defs/node"
                },
                {
                  "type": "string"
                },
                {
                  "type": "number"
                }
              ]
            }
          }
        }
        """#
    )
    var definition: ToolDefinition { Self.definition }

    // Apple's public GenerationSchema supports a restricted JSON Schema subset.
    // Keep the same tool/executor and pass the complete UI as one JSON string.
    static var nativeDefinition: ToolDefinition {
        ToolDefinition(name: name,
                       description: "Pass the complete GenUI document as a JSON-encoded string in document. " + definition.description,
                       parametersJSON: #"{"type":"object","properties":{"document":{"type":"string","description":"Complete JSON GenUI document with title and exactly one of components, ui, or code; optional state and resources."}},"required":["document"],"additionalProperties":false}"#)
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        guard call.argumentsJSON.utf8.count <= 524_288 else { throw GenUIError.invalid("tool arguments exceed 512 KiB") }
        let raw: String
        if let fields = try? JSONDecoder().decode([String: JSONValue].self, from: Data(call.argumentsJSON.utf8)),
           let wrapped = fields["document"] {
            guard fields.count == 1, case .string(let json) = wrapped else { throw GenUIError.invalid("document envelope requires a single JSON string") }
            raw = json
        } else { raw = call.argumentsJSON }
        let document = try GenUIDocument.validated(from: raw)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        return ToolResult(callId: call.id, name: Self.name, content: String(decoding: data, as: UTF8.self))
    }
}
