import Foundation

struct GenUITool: LocalToolExecutor {
    static let name = "genui"
    static let definition = ToolDefinition(
        name: name,
        description: """
        Create a persisted interactive UI. Explicit GenUI requests require this tool, not ASCII/prose. Fix validation errors and retry. Supply title and exactly one of ui, code, or components. Do not infer chart type from IDs/titles; set chartType. After success avoid repeating the UI.
        """ + "\n" + usageGuide + "\nInteractive code example:\n" + interactiveDiagramExample + "\nBasic element properties:\n" + GenUIDocument.coreComponentGuide,
        parametersJSON: #"""
        {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "title": {
              "type": "string",
              "minLength": 1,
              "pattern": "\\S"
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
                    "pattern": "^[A-Za-z_][A-Za-z0-9_]{0,63}$",
                    "description": "Unique input identifier within this document.",
                    "maxLength": 4096
                  },
                  "label": {
                    "type": "string",
                    "minLength": 1,
                    "maxLength": 4096
                  },
                  "kind": {
                    "type": "string",
                    "enum": [
                      "slider",
                      "number",
                      "select",
                      "text",
                      "toggle"
                    ],
                    "maxLength": 4096
                  },
                  "value": {
                    "type": "number",
                    "description": "Numeric default is 0 when omitted. Supply a value within min/max and, for select, equal to one option value. Toggle accepts only 0 or 1."
                  },
                  "text": {
                    "type": "string",
                    "description": "Text default; defaults to empty.",
                    "maxLength": 4096
                  },
                  "min": {
                    "type": "number",
                    "description": "Required for slider. Must be less than max; default value must be at least min."
                  },
                  "max": {
                    "type": "number",
                    "description": "Required for slider. Must be greater than min; default value must be at most max."
                  },
                  "step": {
                    "type": "number",
                    "exclusiveMinimum": 0
                  },
                  "unit": {
                    "type": "string",
                    "maxLength": 4096
                  },
                  "options": {
                    "type": "array",
                    "maxItems": 32,
                    "items": {
                      "type": "object",
                      "properties": {
                        "label": {
                          "type": "string",
                          "minLength": 1,
                          "maxLength": 4096
                        },
                        "value": {
                          "type": "number"
                        }
                      },
                      "required": [
                        "label",
                        "value"
                      ],
                      "additionalProperties": false
                    },
                    "description": "Required and non-empty for select. Values must be distinct and include its default value."
                  }
                },
                "required": [
                  "id",
                  "label",
                  "kind"
                ],
                "additionalProperties": false,
                "oneOf": [
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "slider"
                        ]
                      }
                    },
                    "required": [
                      "min",
                      "max"
                    ]
                  },
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "select"
                        ]
                      },
                      "options": {
                        "minItems": 1
                      }
                    },
                    "required": [
                      "options"
                    ]
                  },
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "toggle"
                        ]
                      },
                      "value": {
                        "enum": [
                          0,
                          1
                        ]
                      }
                    }
                  },
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "number",
                          "text"
                        ]
                      }
                    }
                  }
                ]
              },
              "description": "Legacy components only. IDs must be unique; numeric defaults must satisfy ranges and select options."
            },
            "components": {
              "type": "array",
              "minItems": 1,
              "maxItems": 48,
              "items": {
                "type": "object",
                "properties": {
                  "id": {
                    "type": "string",
                    "pattern": "^[A-Za-z_][A-Za-z0-9_]{0,63}$",
                    "description": "Unique component identifier within this document.",
                    "maxLength": 4096
                  },
                  "kind": {
                    "type": "string",
                    "enum": [
                      "text",
                      "metric",
                      "table",
                      "chart",
                      "cards"
                    ],
                    "maxLength": 4096
                  },
                  "title": {
                    "type": "string",
                    "maxLength": 4096
                  },
                  "text": {
                    "type": "string",
                    "description": "Required for text.",
                    "maxLength": 4096
                  },
                  "value": {
                    "type": "string",
                    "description": "Required for metric; literal or =formula.",
                    "maxLength": 4096
                  },
                  "format": {
                    "type": "string",
                    "enum": [
                      "number",
                      "currency",
                      "percent"
                    ],
                    "maxLength": 4096
                  },
                  "unit": {
                    "type": "string",
                    "maxLength": 4096
                  },
                  "columns": {
                    "type": "array",
                    "maxItems": 12,
                    "items": {
                      "type": "string",
                      "maxLength": 4096
                    },
                    "description": "Required and non-empty for table. Every row must have exactly this many cells."
                  },
                  "rows": {
                    "type": "array",
                    "maxItems": 100,
                    "items": {
                      "type": "array",
                      "items": {
                        "type": "string",
                        "maxLength": 4096
                      }
                    },
                    "description": "Optional table rows; omitted means an empty table. Each row must match columns in length."
                  },
                  "chartType": {
                    "type": "string",
                    "enum": [
                      "line",
                      "pie"
                    ],
                    "description": "Chart only. Omitted means line, never pie. For pie explicitly select pie and provide exactly one series with nonnegative values and a positive total.",
                    "maxLength": 4096
                  },
                  "series": {
                    "type": "array",
                    "maxItems": 8,
                    "items": {
                      "type": "object",
                      "properties": {
                        "name": {
                          "type": "string",
                          "maxLength": 4096
                        },
                        "points": {
                          "type": "array",
                          "maxItems": 100,
                          "items": {
                            "type": "object",
                            "properties": {
                              "label": {
                                "type": "string",
                                "maxLength": 4096
                              },
                              "value": {
                                "type": "string",
                                "description": "Numeric literal or =formula.",
                                "maxLength": 4096
                              }
                            },
                            "required": [
                              "label",
                              "value"
                            ],
                            "additionalProperties": false
                          },
                          "minItems": 1
                        }
                      },
                      "required": [
                        "name",
                        "points"
                      ],
                      "additionalProperties": false
                    },
                    "description": "Required and non-empty for chart; each series needs 1–100 numeric or formula points. Pie requires exactly one series."
                  },
                  "items": {
                    "type": "array",
                    "maxItems": 24,
                    "items": {
                      "type": "object",
                      "properties": {
                        "title": {
                          "type": "string",
                          "maxLength": 4096
                        },
                        "value": {
                          "type": "string",
                          "maxLength": 4096
                        },
                        "detail": {
                          "type": "string",
                          "maxLength": 4096
                        }
                      },
                      "required": [
                        "title",
                        "value"
                      ],
                      "additionalProperties": false
                    },
                    "description": "Required and non-empty for cards."
                  }
                },
                "required": [
                  "id",
                  "kind"
                ],
                "additionalProperties": false,
                "oneOf": [
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "text"
                        ]
                      }
                    },
                    "required": [
                      "text"
                    ]
                  },
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "metric"
                        ]
                      }
                    },
                    "required": [
                      "value"
                    ]
                  },
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "table"
                        ]
                      },
                      "columns": {
                        "minItems": 1
                      }
                    },
                    "required": [
                      "columns"
                    ]
                  },
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "chart"
                        ]
                      },
                      "series": {
                        "minItems": 1
                      }
                    },
                    "required": [
                      "series"
                    ],
                    "oneOf": [
                      {
                        "properties": {
                          "chartType": {
                            "enum": [
                              "pie"
                            ]
                          },
                          "series": {
                            "maxItems": 1
                          }
                        },
                        "required": [
                          "chartType"
                        ]
                      },
                      {
                        "properties": {
                          "chartType": {
                            "enum": [
                              "line"
                            ]
                          }
                        }
                      }
                    ]
                  },
                  {
                    "properties": {
                      "kind": {
                        "enum": [
                          "cards"
                        ]
                      },
                      "items": {
                        "minItems": 1
                      }
                    },
                    "required": [
                      "items"
                    ]
                  }
                ]
              },
              "description": "Legacy renderer. Multiple text/table sections are automatically collapsed by the iOS host; use ui/code when essential sections must stay visible."
            },
            "ui": {
              "type": "object",
              "description": "Component tree. Basic types/properties are listed below; use genui_reference only for missing template or alias contracts. Children may contain nodes, strings or numbers; validated locally.",
              "properties": {
                "type": {
                  "type": "string"
                },
                "props": {
                  "type": "object"
                },
                "children": {
                  "type": "array",
                  "items": {
                    "anyOf": [
                      {
                        "type": "object"
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
              },
              "required": [
                "type"
              ],
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
                  },
                  {
                    "required": [
                      "state"
                    ]
                  },
                  {
                    "required": [
                      "resources"
                    ]
                  }
                ]
              },
              "properties": {
                "title": {
                  "maxLength": 4096
                },
                "subtitle": {
                  "maxLength": 4096
                }
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
              },
              "properties": {
                "inputs": {
                  "maxItems": 0
                }
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
              },
              "properties": {
                "inputs": {
                  "maxItems": 0
                }
              }
            }
          ]
        }
        """#
    )
    // This core is fixed. Retrieved template/alias details are appended only as tool results.
    static let usageGuide = """
        Use basic elements directly for ordinary layouts. Find templates/aliases via genui_reference(componentName:"*",query:...), then read an exact name for contracts; @guide repeats this guide. Reuse history. Templates use props:{__state:verifiedData}; no automatic data fetching or backend actions. Never invent data or success.
        ui/code: return DIL.h(type,props,...children), __dil.jsx, or call DIL.render. Canonical names are globals. Hooks: DIL.useState/useMemo/useEffect/useCallback/useRef/useId/useAppData/useConstants/useTheme/useBreakpoint/useIsMobile/useNow/useSpeechSynthesizer. State must be JSON serializable. Calculations use JavaScript, including Math.pow. No imports, raw JSX, remote scripts or protocol fallbacks; AI turns use the existing Pi path.
        bind:"key", {{key}} and {{object.field}} read state; whole interpolations retain types. onChange:{type:"setState",key:"key",value:"$value"} writes state. Events: setState/resetState/copy/openUrl/issueNewTurn/openEntityDetail/openMap. External host actions and new turns require user gestures. Each uses items/of, itemName/item, indexName/index; Scope uses values; Show uses when and Show.Else. $-prefixed props use the original CEL parser/evaluator, e.g. "$value":"price * quantity".
        Numeric spacing is 4px per unit; default gap is 2. Colors accept semantic tokens or {light,dark}; padding/margin accept numbers, CSS lengths or {x,y,top,right,bottom,left}. Avoid repeating the document heading. Chart.content needs chartType and matching data keys. Use markdown {text} for headings, prose and fenced code; text is for labels. Media needs explicit HTTPS URLs; Lottie also accepts animationData and YouTube videoId. MapWidgetV2 uses supplied places/coordinates; AppBlock uses inline content. Device limits apply.
        """
    // Small working example keeps the advertised tool within its context budget.
    static let interactiveDiagramExample = #"""
    const h=DIL.h;
    const [n,setN]=DIL.useState(0);
    return h('col',{},h('svg',{viewBox:'0 0 200 60',width:'100%',height:60},h('path',{d:'M20 30 H180',stroke:'currentColor',strokeWidth:2}),h('circle',{cx:n?180:20,cy:30,r:8,fill:'currentColor'})),h('text',{},n?'Step 2':'Step 1'),h('button',{label:'Switch step',onClick:()=>setN(1-n)}));
    """#

    static let worktreeDiagramExample = #"""
    const h = DIL.h;
    const [mode, setMode] = DIL.useState('worktree');
    const [selected, setSelected] = DIL.useState(0);
    const [dirty, setDirty] = DIL.useState([false, false, false]);
    const branches = ['main', 'feature/login', 'fix/crash'];
    const folders = ['project/', 'project-feature/', 'project-fix/'];
    const indices = mode === 'worktree' ? [0, 1, 2] : [selected];
    return h('col', {gap:4},
      h('segmented-control', {label:'表示モード', value:mode,
        options:[{label:'通常のGit',value:'normal'},{label:'Git worktree',value:'worktree'}], onChange:setMode}),
      h('card', {padding:3}, h('title', {size:'md'}, '共有Gitリポジトリ'),
        h('text', {}, 'コミット履歴・ブランチ参照・Gitオブジェクトを共有'),
        h('svg', {viewBox:'0 0 300 60',width:'100%',height:60,ariaLabel:'リポジトリから作業フォルダへの接続'},
          h('path', {d:mode === 'worktree' ? 'M150 0 V20 M50 55 V20 H250 V55 M150 20 V55' : 'M150 0 V55',fill:'none',stroke:'currentColor',strokeWidth:2}))),
      h('grid', {minChildWidth:140,gap:2}, ...indices.map(i =>
        h('pressable', {ariaLabel:(mode === 'normal' ? 'project/' : folders[i])+' · '+branches[i]+(dirty[i] ? ' · 変更あり' : ' · 変更なし'),
          direction:'column',gap:2,padding:3,border:true,radius:12,background:selected === i ? 'surface-tertiary' : 'surface',onClick:()=>setSelected(i)},
          h('icon',{name:'folder',color:selected === i ? 'info' : 'secondary'}),
          h('text',{strong:true},mode === 'normal' ? 'project/' : folders[i]),
          h('caption',{},branches[i]),h('badge',{color:dirty[i]?'warning':'success',label:dirty[i]?'変更あり':'変更なし'})))),
      mode === 'normal' && h('select', {label:'ブランチを切り替える（デモ）',disabled:dirty[selected],value:String(selected),
        options:branches.map((label,i)=>({label,value:String(i)})),onChange:value=>setSelected(Number(value))}),
      h('card', {padding:3}, h('title', {size:'md'}, '選択中：'+branches[selected]),
        h('text', {}, mode === 'worktree' ? '各フォルダの未コミット変更は独立して保持されます。' : '1つの作業フォルダでブランチを切り替えます。このデモでは変更を戻してから切り替えてください。'),
        h('button', {label:'ファイルを編集（デモ）',block:true,onClick:()=>setDirty(old=>old.map((v,i)=>i===selected?true:v))}),
        h('button', {label:'変更を戻す（デモ）',onClick:()=>setDirty(old=>old.map((v,i)=>i===selected?false:v))}),
        h('caption', {}, '操作はこの図の中だけで完結し、実際のGitやファイルは変更しません。')));
    """#
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
