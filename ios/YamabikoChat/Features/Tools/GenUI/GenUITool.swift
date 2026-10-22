import Foundation

struct GenUITool: LocalToolExecutor {
    static let name = "genui"
    static let definition = ToolDefinition(
        name: name,
        description: """
        Save a UI document. Follow the system category rules. Supply a title and exactly one of ui, code, or components. If validation fails, correct the reported errors before retrying. Do not infer chart type from IDs/titles; set chartType explicitly. Include key facts in the text response as well.
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
        Use basic elements directly for ordinary layouts. For templates or aliases, search genui_reference(componentName:"*",query:...), then read the exact name's contract. Supply verified data in props.__state matching that contract; template backend actions are unsupported.

        Renderers: ui is a component tree; code is a JavaScript function body returning nodes with DIL.h(type, props, ...children), __dil.jsx, or DIL.render. JSX syntax, imports, and remote scripts are unavailable. Available hooks: DIL.useState/useEffect/useMemo/useRef/useTheme/useBreakpoint. Use JavaScript arithmetic and Math.min/Math.max/Math.abs/Math.round/Math.pow in code. Legacy components use their separate =expression language.

        Keep state JSON serializable. In code, const [mode,setMode]=DIL.useState(initial) pairs value:mode with onChange:setMode; derive dependent content from mode. An object setState action writes document state and cannot change a hook variable. For document state, initialize state:{mode:...}, read with bind:"mode", {{mode}}, or state.mode, and write with onChange:{type:"setState",key:"mode",value:"$value"}. External actions require user gestures.

        Tree helpers: Each uses items/of, itemName and indexName; Scope uses values; Show uses when and Show.Else. Properties prefixed with $ evaluate CEL, for example "$value":"price * quantity".

        Processes: list {connector:true,marker:"none"} with separate list-item {label,description}. Comparisons: grid {minChildWidth:160}. Text sizes use sm/md/lg/xl. Text preserves newlines; preserveWhitespace:true also preserves spaces. Spacing is 4px per unit; default gap is 2. Padding/margin accept numbers, CSS strings, or edge objects. Colors accept theme tokens or {light,dark}. Use markdown {text} for prose or code.

        Charts: set the type and match data keys explicitly. Legacy kind:"chart" defaults to a line chart; chartType:"pie" requires one series of finite nonnegative values with a positive total. Rich Chart uses props.content, for example {chartType:"bar",data:[{label:"A",score:12}],xKey:"label",series:[{dataKey:"score",label:"Score"}]} or {chartType:"pie",data:[{name:"A",value:40},{name:"B",value:60}],nameKey:"name",valueKey:"value"}.

        Media requires HTTPS URLs. MapWidgetV2 displays supplied places on a native map: points and origin accept a title/name, address, or query resolved by Apple MapKit. Prefer a specific place name with city/address; coordinates are optional. Routes require show_route. A widget does not retrieve or verify live data by itself.
        """
    // Concrete examples teach visual structure and meaningful local state together.
    static let interactiveDiagramExample = #"""
    const h=DIL.h;
    const [step,setStep]=DIL.useState(0);
    const stages=[['アプリ','ログイン情報を入力'],['認証サーバー','本人確認を行う'],['アプリ','発行されたトークンを受け取る'],['API','トークンを検証し、権限に応じて応答']];
    return h('col',{gap:3},
      h('title',{size:'lg'},'認証の流れ'),
      h('segmented-control',{label:'ステップ',value:step,onChange:setStep,options:stages.map(([label],value)=>({label,value}))}),
      h('list',{connector:true,marker:'none'},...stages.map(([label,description],i)=>
        h('list-item',{key:String(i),label:(i+1)+'. '+label,description,variant:i===step?'success':'outline'}))),
      h('text',{strong:true},'現在：'+stages[step][1]),
      h('button',{label:step===stages.length-1?'最初から':'次のステップ',onClick:()=>setStep((step+1)%stages.length)}),
      h('caption',{},'説明用デモ（通信なし）'));
    """#

    static let powersExample = #"""
    const h=DIL.h;
    const [base,setBase]=DIL.useState(2),[exponent,setExponent]=DIL.useState(3);
    const result=Math.pow(base,exponent);
    return h('col',{gap:3},
      h('title',{size:'lg'},'pow：べき乗を試す'),
      h('text',{},'指数が正の整数なら、底をその回数だけ掛けます。'),
      h('grid',{minChildWidth:160,gap:3},
        h('col',{},h('label',{},'底：'+base),h('slider',{label:'底',min:1,max:5,step:1,value:base,onChange:setBase})),
        h('col',{},h('label',{},'指数：'+exponent),h('slider',{label:'指数',min:0,max:5,step:1,value:exponent,onChange:setExponent}))),
      h('card',{variant:'soft',padding:3},
        h('title',{size:'xl',tabularNums:true},'pow('+base+', '+exponent+') = '+result),
        h('text',{},exponent===0?'0乗は1':Array(exponent).fill(base).join(' × ')+' = '+result)),
      h('caption',{},'このデモの底は1〜5、指数は0〜5の整数です。一般のpowは負数や小数も扱います。'));
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
        try document(from: arguments, isPreview: false)
    }

    static func previewDocument(from arguments: String) throws -> GenUIDocument {
        try document(from: arguments, isPreview: true)
    }

    private static func document(from arguments: String, isPreview: Bool) throws -> GenUIDocument {
        let raw: String
        let fields = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)) as? [String: Any]
        var documentFields = fields
        // Inspect only the optional native-model envelope. Recursively decoding
        // every UI/state value here repeats the real document decoder's work on
        // every preview, including multiple failed scalar type probes per value.
        if let fields,
           let wrapped = fields["document"] {
            guard fields.count == 1, let json = wrapped as? String else { throw GenUIError.invalid("document envelope requires a single JSON string") }
            raw = json
            if isPreview { documentFields = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] }
        } else { raw = arguments }
        // Most code deltas are syntactically incomplete. Reject them before
        // decoding the whole document; a visible preview still passes ALL normal
        // document checks below, and execution always uses the regular path.
        if isPreview, let code = documentFields?["code"] as? String {
            try GenUICodeValidator.validate(code)
        }
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
