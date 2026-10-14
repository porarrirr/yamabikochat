import Foundation

struct GenUITool: LocalToolExecutor {
    static let name = "genui"
    static let definition = ToolDefinition(
        name: name,
        description: """
        Create a persisted interactive calculator, chart, table, map or form in the conversation. Supply title and exactly one of code, ui, or legacy components. code is a client-side JavaScript function body returning DIL.h(type,props,...children); no imports or raw JSX. ui is a tree of {type,props,children} with optional state bindings.
        Runtime rules and basic element properties follow below. Discover original templates and aliases with genui_reference(componentName:"*") and optional query; read a specific name for supported properties and original template source/state contract. Reuse retrieved contracts from conversation history. componentName:"@guide" retrieves runtime guidance if it is needed again. Provide verified data in __state for original templates; a name does not fetch data. Backend actions are unsupported. Never fabricate live data or action success.
        Do not infer chart type from IDs/titles. Use explicit chartType for charts. External media must use explicit HTTPS URLs; host actions require user gestures. AI turns use the existing Pi path. After success, briefly explain the UI.
        """ + "\n" + usageGuide + "\nBasic element properties:\n" + GenUIDocument.coreComponentGuide,
        parametersJSON: #"""
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "title": {
              "type": "string"
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
                  "chartType": {
                    "type": "string",
                    "enum": ["line", "pie"],
                    "description": "Chart only. Omitted means line, never pie. For pie explicitly select pie and provide exactly one series with nonnegative values and a positive total."
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
              "type": "object",
              "description": "Component tree. Look up type and props with genui_reference. children may contain nodes, strings or numbers; validated locally.",
              "properties": {
                "type": { "type": "string" },
                "props": { "type": "object" },
                "children": { "type": "array", "items": { "anyOf": [{ "type": "object" }, { "type": "string" }, { "type": "number" }] } }
              },
              "required": ["type"],
              "additionalProperties": false
            },
            "code": {
              "type": "string",
              "description": "JavaScript function body returning DIL.h(type,props,...children). Client-side only; DIL hooks are available."
            },
            "state": {
              "type": "object"
            },
            "resources": {
              "type": "object",
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
          ]
        }
        """#
    )
    // This core is fixed. Retrieved template/alias details are appended only as tool results.
    static let usageGuide = """
        Create a persisted interactive GenUI in the conversation using exactly one of ui or code. Prefer the recovered original components for matching tasks: call genui_reference to inspect their actual source/state contract, then use {type:componentName,props:{__state:verifiedData}} or DIL.h(componentName,{__state:verifiedData}). There are 283 original templates including learning, calculators, clocks, timers, currency, weather, finance, sports and entity views. Their layout, calculations and local state handlers are preserved. A component name does not fetch data; provide the complete __state contract. Reference server actions/refresh require the original backend and return an unsupported reason. Never manufacture missing live data or claim those actions succeeded.
        code is a JavaScript function body returning DIL.h(type,props,...children), __dil.jsx, or calling DIL.render. Compiled canonical component names are also available as globals. DIL.useState/useMemo/useEffect/useCallback/useRef/useId/useAppData/useConstants/useTheme/useBreakpoint/useIsMobile/useNow/useSpeechSynthesizer are supported. useTheme returns {theme,isDark}; useBreakpoint(token) returns whether the recovered breakpoint is active (xs380,sm576,md768,lg1024,xl1280,2xl1536). AI execution and follow-up turns remain on the existing Pi path. Local calculations support JavaScript Math.pow/Math.min/Math.max/Math.round and custom functions. No imports or raw JSX syntax.
        When composing primitives, follow the reference metrics and hierarchy, without adding a second document heading or decorative enclosing panel. Numeric spacing is 4px per unit; default container gap is 2 units. Cards use original default/soft surfaces, padding and radii. Dimensions and justification are retained on phones. Text/title/caption use the original iOS typography and icons use the original SVG assets. Theme colors accept semantic tokens or {light,dark}. Padding/margin accept numbers, CSS lengths or {x,y,top,right,bottom,left}.
        Declarative bindings use bind:"key", {{key}} / {{object.field}}, and onChange:{type:"setState",key:"key",value:"$value"}. Whole interpolations retain types. Events support setState/resetState/copy/openUrl/issueNewTurn/openEntityDetail/openMap; external host actions require user gestures. Each supports items/of, itemName/item, indexName/index. Scope supplies values; Show uses when with Show.Else. Props prefixed with $ use the exact original CEL parser/evaluator against the current binding scope, for example "$value":"price * quantity" or Each "$items":"rows.filter(row, row.active)". CEL maps/collections and its original standard library are supported locally.
        chart accepts data,series,xAxis,yAxis and showLegend/showXAxis/showYAxis/showGrid; series carry dataKey,label,type,color. pie-chart also accepts innerRadius and row fill/stroke. Do not infer chart type from IDs/titles. Legacy chart types remain line/pie. Chart.content accepts explicit chartType bar/line/area/scatter/pie or supported Recharts JSON. flashcard-flip retains both faces and supports controlled flipped, reducedMotion and swipe handlers. Markdown supports nested lists, tables, code and math. Lottie accepts animationData or explicit HTTPS src; YouTube accepts videoId/url and embeds its player. Media resources must be explicit HTTPS. MapWidgetV2 renders native inline MapKit with supplied places/coordinates. AppBlock uses inline content. Do not add remote scripts, hidden model calls, or protocol fallbacks.
        Rich documents retain saved compatibility; device limits still apply. Look up individual supported properties with genui_reference(componentName: name).
        """
    var definition: ToolDefinition { Self.definition }

    // Apple's public GenerationSchema supports a restricted JSON Schema subset.
    // Keep the same tool/executor and pass the complete UI as one JSON string.
    static var nativeDefinition: ToolDefinition {
        ToolDefinition(name: name,
                       description: "Pass the complete GenUI document as a JSON-encoded string in document. " + definition.description,
                       parametersJSON: #"{"type":"object","properties":{"document":{"type":"string","description":"Complete JSON GenUI document with title and exactly one of components, ui, or code; optional state and resources."}},"required":["document"],"additionalProperties":false}"#)
    }

    static func document(from arguments: String) throws -> GenUIDocument {
        let raw: String
        if let fields = try? JSONDecoder().decode([String: JSONValue].self, from: Data(arguments.utf8)),
           let wrapped = fields["document"] {
            guard fields.count == 1, case .string(let json) = wrapped else { throw GenUIError.invalid("document envelope requires a single JSON string") }
            raw = json
        } else { raw = arguments }
        return try GenUIDocument.validated(from: raw)
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        let document = try Self.document(from: call.argumentsJSON)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        return ToolResult(callId: call.id, name: Self.name, content: String(decoding: data, as: UTF8.self))
    }
}
