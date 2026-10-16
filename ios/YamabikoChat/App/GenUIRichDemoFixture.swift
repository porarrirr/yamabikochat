import Foundation

enum GenUIRichDemoFixture {
    static let title = "GenUI コンポーネント"

    @MainActor
    static func seed(chatRepository: ChatRepository, conversations: ConversationRepository, timestamp: Int64) throws {
        let messageID: Int64
        if let id = try conversations.siriConversations(matching: title).first(where: { $0.title == title })?.id,
           let existing = try conversations.fetchLastAssistantMessage(conversationId: id)?.id {
            messageID = existing
        } else {
            let id = try chatRepository.createConversation(title: title)
            messageID = try conversations.insertMessage(ChatMessage(conversationId: id, role: "assistant", text: "部品の状態を共有し、グラフやカードを同時に更新できます。", createdAtMs: timestamp))
        }
        let catalogJSON = #"""
{
  "ui": {
    "type": "col",
    "props": {
      "gap": 6
    },
    "children": [
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "文字・装飾"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "text, title, caption, label, badge, bold, italic, underline, strikethrough, code, math, blockquote"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "text"
                    ]
                  },
                  {
                    "type": "text",
                    "props": {},
                    "children": [
                      "通常の本文テキスト。複数行は幅に合わせて折り返します。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "title"
                    ]
                  },
                  {
                    "type": "title",
                    "props": {
                      "size": "lg"
                    },
                    "children": [
                      "画面内の見出し"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "caption"
                    ]
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "補助説明や注釈に使う小さな文字"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "label"
                    ]
                  },
                  {
                    "type": "label",
                    "props": {
                      "weight": 650
                    },
                    "children": [
                      "入力項目のラベル"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "badge"
                    ]
                  },
                  {
                    "type": "badge",
                    "props": {
                      "label": "完了",
                      "color": "success",
                      "pill": true
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "bold / italic"
                    ]
                  },
                  {
                    "type": "text",
                    "props": {},
                    "children": [
                      {
                        "type": "bold",
                        "props": {},
                        "children": [
                          "太字"
                        ]
                      },
                      " ・ ",
                      {
                        "type": "italic",
                        "props": {},
                        "children": [
                          "斜体"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "underline / strikethrough"
                    ]
                  },
                  {
                    "type": "text",
                    "props": {},
                    "children": [
                      {
                        "type": "underline",
                        "props": {},
                        "children": [
                          "下線"
                        ]
                      },
                      " ・ ",
                      {
                        "type": "strikethrough",
                        "props": {},
                        "children": [
                          "取り消し線"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "code"
                    ]
                  },
                  {
                    "type": "text",
                    "props": {},
                    "children": [
                      "設定値 ",
                      {
                        "type": "code",
                        "props": {},
                        "children": [
                          "theme = \"light\""
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "math"
                    ]
                  },
                  {
                    "type": "math",
                    "props": {
                      "value": "a² + b² = c²",
                      "block": true
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "数式エンジンがない環境では式の文字列を表示"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "blockquote"
                    ]
                  },
                  {
                    "type": "blockquote",
                    "props": {},
                    "children": [
                      "大事な前提や引用を、左罫線付きで表示します。"
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "レイアウト"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "box, row, col, grid, grid-item, flow, flow-item, card, divider, spacer"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "box"
                    ]
                  },
                  {
                    "type": "box",
                    "props": {
                      "padding": 3,
                      "gap": 2,
                      "background": "var(--soft)",
                      "border": "1px solid var(--border)",
                      "radius": 3
                    },
                    "children": [
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "まとまりを囲う箱"
                        ]
                      },
                      {
                        "type": "caption",
                        "props": {},
                        "children": [
                          "余白・背景・境界線を指定"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "row"
                    ]
                  },
                  {
                    "type": "row",
                    "props": {
                      "justify": "between",
                      "align": "center"
                    },
                    "children": [
                      {
                        "type": "badge",
                        "props": {
                          "label": "左"
                        },
                        "children": []
                      },
                      {
                        "type": "badge",
                        "props": {
                          "label": "右"
                        },
                        "children": []
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "col"
                    ]
                  },
                  {
                    "type": "col",
                    "props": {
                      "gap": 2
                    },
                    "children": [
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "上の行"
                        ]
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "下の行"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "grid + grid-item"
                    ]
                  },
                  {
                    "type": "grid",
                    "props": {
                      "columns": 2,
                      "gap": 2
                    },
                    "children": [
                      {
                        "type": "grid-item",
                        "props": {
                          "span": 1
                        },
                        "children": [
                          {
                            "type": "card",
                            "props": {
                              "padding": 2
                            },
                            "children": [
                              "セル A"
                            ]
                          }
                        ]
                      },
                      {
                        "type": "grid-item",
                        "props": {
                          "span": 1
                        },
                        "children": [
                          {
                            "type": "card",
                            "props": {
                              "padding": 2
                            },
                            "children": [
                              "セル B"
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "flow + flow-item"
                    ]
                  },
                  {
                    "type": "flow",
                    "props": {
                      "layout": "row",
                      "gap": 2
                    },
                    "children": [
                      {
                        "type": "flow-item",
                        "props": {
                          "padding": 2,
                          "background": "var(--soft)"
                        },
                        "children": [
                          "flow A"
                        ]
                      },
                      {
                        "type": "flow-item",
                        "props": {
                          "padding": 2,
                          "background": "var(--soft)"
                        },
                        "children": [
                          "flow B"
                        ]
                      },
                      {
                        "type": "flow-item",
                        "props": {
                          "padding": 2,
                          "background": "var(--soft)"
                        },
                        "children": [
                          "flow C"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "card"
                    ]
                  },
                  {
                    "type": "card",
                    "props": {
                      "padding": 3,
                      "shadow": true
                    },
                    "children": [
                      {
                        "type": "title",
                        "props": {
                          "size": "md"
                        },
                        "children": [
                          "情報カード"
                        ]
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "枠・背景・角丸で内容をひとまとまりにします。"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "divider"
                    ]
                  },
                  {
                    "type": "col",
                    "props": {
                      "gap": 2
                    },
                    "children": [
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "セクション A"
                        ]
                      },
                      {
                        "type": "divider",
                        "props": {
                          "color": "var(--accent)",
                          "size": 1
                        },
                        "children": []
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "セクション B"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "spacer"
                    ]
                  },
                  {
                    "type": "box",
                    "props": {
                      "height": 92,
                      "padding": 2,
                      "border": "1px solid var(--border)",
                      "radius": 2
                    },
                    "children": [
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "上"
                        ]
                      },
                      {
                        "type": "spacer",
                        "props": {
                          "minSize": "lg"
                        },
                        "children": []
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "下"
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "入力・操作"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "button, pressable, input, textarea, slider, checkbox, select, segmented-control, radio-group, radio, date-picker, form"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "button"
                    ]
                  },
                  {
                    "type": "button",
                    "props": {
                      "label": "状態を更新",
                      "onClick": {
                        "type": "setState",
                        "key": "status",
                        "value": "ボタンをタップしました"
                      }
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "pressable"
                    ]
                  },
                  {
                    "type": "pressable",
                    "props": {
                      "padding": 3,
                      "border": "1px solid var(--border)",
                      "radius": 2,
                      "onClick": {
                        "type": "setState",
                        "key": "status",
                        "value": "カードをタップしました"
                      }
                    },
                    "children": [
                      {
                        "type": "bold",
                        "props": {},
                        "children": [
                          "タップ可能な領域"
                        ]
                      },
                      {
                        "type": "caption",
                        "props": {},
                        "children": [
                          "押すとアクションを実行"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "input"
                    ]
                  },
                  {
                    "type": "input",
                    "props": {
                      "name": "name",
                      "bind": "name",
                      "placeholder": "文字を入力"
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "textarea"
                    ]
                  },
                  {
                    "type": "textarea",
                    "props": {
                      "name": "note",
                      "bind": "status",
                      "rows": 2,
                      "placeholder": "複数行入力"
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "slider"
                    ]
                  },
                  {
                    "type": "col",
                    "props": {},
                    "children": [
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "値: {{volume}}"
                        ]
                      },
                      {
                        "type": "slider",
                        "props": {
                          "name": "volume",
                          "bind": "volume",
                          "min": 0,
                          "max": 100,
                          "step": 1,
                          "marks": [
                            0,
                            50,
                            100
                          ]
                        },
                        "children": []
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "checkbox"
                    ]
                  },
                  {
                    "type": "checkbox",
                    "props": {
                      "bind": "enabled",
                      "checked": true,
                      "label": "有効にする"
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "select"
                    ]
                  },
                  {
                    "type": "select",
                    "props": {
                      "name": "プラン",
                      "bind": "mode",
                      "options": [
                        {
                          "label": "ライト",
                          "value": "light"
                        },
                        {
                          "label": "ダーク",
                          "value": "dark"
                        }
                      ]
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "segmented-control"
                    ]
                  },
                  {
                    "type": "segmented-control",
                    "props": {
                      "label": "表示密度",
                      "bind": "choice",
                      "options": [
                        {
                          "label": "標準",
                          "value": "A"
                        },
                        {
                          "label": "広め",
                          "value": "B"
                        }
                      ]
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "radio-group"
                    ]
                  },
                  {
                    "type": "radio-group",
                    "props": {
                      "label": "配送方法",
                      "bind": "choice"
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "現行validatorでは options が許可されないため、選択肢なしの枠として表示。個別radioは下の例。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "radio"
                    ]
                  },
                  {
                    "type": "row",
                    "props": {
                      "align": "center",
                      "gap": 2
                    },
                    "children": [
                      {
                        "type": "radio",
                        "props": {
                          "value": "one"
                        },
                        "children": []
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "単独のラジオ項目"
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "date-picker"
                    ]
                  },
                  {
                    "type": "date-picker",
                    "props": {
                      "bind": "date",
                      "placeholder": "日付を選択",
                      "clearable": true
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "form"
                    ]
                  },
                  {
                    "type": "form",
                    "props": {
                      "onSubmit": {
                        "type": "setState",
                        "key": "formStatus",
                        "value": "送信しました"
                      }
                    },
                    "children": [
                      {
                        "type": "input",
                        "props": {
                          "name": "email",
                          "inputType": "email",
                          "placeholder": "メールアドレス"
                        },
                        "children": []
                      },
                      {
                        "type": "button",
                        "props": {
                          "label": "送信",
                          "submit": true
                        },
                        "children": []
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "共有状態"
                    ]
                  },
                  {
                    "type": "col",
                    "props": {
                      "gap": 1
                    },
                    "children": [
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "名前: {{name}}"
                        ]
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "スライダー: {{volume}}"
                        ]
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "状態: {{status}}"
                        ]
                      },
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "フォーム: {{formStatus}}"
                        ]
                      }
                    ]
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "上の入力操作で同じstateが変わります。"
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "表・リスト"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "table, table-section, table-row, table-cell, list, list-item"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "table + section / row / cell"
                    ]
                  },
                  {
                    "type": "table",
                    "props": {
                      "stickyHeader": true
                    },
                    "children": [
                      {
                        "type": "table-section",
                        "props": {
                          "header": "今月の実績"
                        },
                        "children": [
                          {
                            "type": "table-row",
                            "props": {
                              "header": true
                            },
                            "children": [
                              {
                                "type": "table-cell",
                                "props": {
                                  "header": true
                                },
                                "children": [
                                  "月"
                                ]
                              },
                              {
                                "type": "table-cell",
                                "props": {
                                  "header": true
                                },
                                "children": [
                                  "件数"
                                ]
                              },
                              {
                                "type": "table-cell",
                                "props": {
                                  "header": true
                                },
                                "children": [
                                  "状態"
                                ]
                              }
                            ]
                          },
                          {
                            "type": "table-row",
                            "props": {},
                            "children": [
                              {
                                "type": "table-cell",
                                "props": {},
                                "children": [
                                  "1月"
                                ]
                              },
                              {
                                "type": "table-cell",
                                "props": {},
                                "children": [
                                  "24"
                                ]
                              },
                              {
                                "type": "table-cell",
                                "props": {},
                                "children": [
                                  "完了"
                                ]
                              }
                            ]
                          },
                          {
                            "type": "table-row",
                            "props": {},
                            "children": [
                              {
                                "type": "table-cell",
                                "props": {
                                  "rowSpan": 1
                                },
                                "children": [
                                  "2月"
                                ]
                              },
                              {
                                "type": "table-cell",
                                "props": {
                                  "colSpan": 2
                                },
                                "children": [
                                  "準備中"
                                ]
                              }
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "list + list-item"
                    ]
                  },
                  {
                    "type": "list",
                    "props": {
                      "marker": "number",
                      "start": 1,
                      "connector": true
                    },
                    "children": [
                      {
                        "type": "list-item",
                        "props": {
                          "label": "入力する",
                          "description": "条件をスライダーやフォームで指定"
                        },
                        "children": []
                      },
                      {
                        "type": "list-item",
                        "props": {
                          "label": "結果を見る",
                          "description": "KPI・表・グラフを確認"
                        },
                        "children": []
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "複合表示"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "carousel, carousel-item, carousel-media-item, popover, popover-trigger, popover-content"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "carousel + carousel-item"
                    ]
                  },
                  {
                    "type": "carousel",
                    "props": {
                      "showArrows": true,
                      "visibleItems": 1,
                      "snap": true
                    },
                    "children": [
                      {
                        "type": "carousel-item",
                        "props": {
                          "padding": 3,
                          "background": "var(--soft)"
                        },
                        "children": [
                          {
                            "type": "title",
                            "props": {
                              "size": "md"
                            },
                            "children": [
                              "カード 1"
                            ]
                          },
                          {
                            "type": "text",
                            "props": {},
                            "children": [
                              "横へスワイプ"
                            ]
                          }
                        ]
                      },
                      {
                        "type": "carousel-item",
                        "props": {
                          "padding": 3,
                          "background": "var(--soft)"
                        },
                        "children": [
                          {
                            "type": "title",
                            "props": {
                              "size": "md"
                            },
                            "children": [
                              "カード 2"
                            ]
                          },
                          {
                            "type": "text",
                            "props": {},
                            "children": [
                              "矢印でも移動"
                            ]
                          }
                        ]
                      },
                      {
                        "type": "carousel-item",
                        "props": {
                          "padding": 3,
                          "background": "var(--soft)"
                        },
                        "children": [
                          {
                            "type": "title",
                            "props": {
                              "size": "md"
                            },
                            "children": [
                              "カード 3"
                            ]
                          },
                          {
                            "type": "text",
                            "props": {},
                            "children": [
                              "スナップ位置で停止"
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "carousel-media-item"
                    ]
                  },
                  {
                    "type": "carousel",
                    "props": {
                      "visibleItems": 1
                    },
                    "children": [
                      {
                        "type": "carousel-media-item",
                        "props": {
                          "padding": 2,
                          "media": {
                            "type": "AsyncImage",
                            "props": {
                              "ref": "mountain",
                              "alt": "山と湖"
                            }
                          }
                        },
                        "children": []
                      }
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "popover family"
                    ]
                  },
                  {
                    "type": "popover",
                    "props": {
                      "open": false
                    },
                    "children": [
                      {
                        "type": "popover-trigger",
                        "props": {},
                        "children": [
                          "補足を開く"
                        ]
                      },
                      {
                        "type": "popover-content",
                        "props": {
                          "showCloseButton": true,
                          "side": "bottom"
                        },
                        "children": [
                          {
                            "type": "text",
                            "props": {},
                            "children": [
                              "文書の流れの中に展開される補足です。"
                            ]
                          }
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "メディア・アイコン"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "AsyncImage, AsyncImageGroup, AsyncVideo, favicon, icon"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "AsyncImage"
                    ]
                  },
                  {
                    "type": "AsyncImage",
                    "props": {
                      "ref": "mountain",
                      "alt": "山と湖の写真",
                      "height": 155,
                      "fit": "cover",
                      "radius": 3
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "HTTPS resourceから読み込み。通信不可ならfallbackを表示。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "AsyncImageGroup"
                    ]
                  },
                  {
                    "type": "AsyncImageGroup",
                    "props": {
                      "refs": [
                        "mountain",
                        "coast"
                      ],
                      "layout": "row",
                      "size": "sm",
                      "fallback": "画像を読み込めません"
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "AsyncVideo"
                    ]
                  },
                  {
                    "type": "AsyncVideo",
                    "props": {
                      "ref": "flowerVideo"
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "動画の再生コントロール付き。サンプル動画の取得には通信が必要です。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "favicon"
                    ]
                  },
                  {
                    "type": "favicon",
                    "props": {
                      "url": "https://example.org",
                      "alt": "Example favicon",
                      "size": 28
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "resourcesのキーにURLを指定し、画像URLを対応付けた例。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "icon"
                    ]
                  },
                  {
                    "type": "row",
                    "props": {
                      "gap": 3,
                      "align": "center"
                    },
                    "children": [
                      {
                        "type": "icon",
                        "props": {
                          "name": "check",
                          "size": 24
                        },
                        "children": []
                      },
                      {
                        "type": "icon",
                        "props": {
                          "name": "heart",
                          "size": 24
                        },
                        "children": []
                      },
                      {
                        "type": "icon",
                        "props": {
                          "name": "map",
                          "size": 24
                        },
                        "children": []
                      },
                      {
                        "type": "icon",
                        "props": {
                          "name": "unknown-name",
                          "size": 24
                        },
                        "children": []
                      }
                    ]
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "既知glyphは記号、未知名は代替glyphで表示。"
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "グラフ"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "Chart: bar / line / scatter / pie"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "Chart · bar"
                    ]
                  },
                  {
                    "type": "Chart",
                    "props": {
                      "content": {
                        "chartType": "bar",
                        "data": [
                          {
                            "month": "1月",
                            "x": 1,
                            "amount": 24,
                            "target": 30,
                            "name": "基本",
                            "share": 45
                          },
                          {
                            "month": "2月",
                            "x": 2,
                            "amount": 42,
                            "target": 38,
                            "name": "追加",
                            "share": 30
                          },
                          {
                            "month": "3月",
                            "x": 3,
                            "amount": 33,
                            "target": 48,
                            "name": "継続",
                            "share": 25
                          }
                        ],
                        "xKey": "month",
                        "valueKey": "amount",
                        "yAxisMin": 0,
                        "yAxisMax": 60,
                        "xAxisLabel": "月",
                        "valueSuffix": " pt",
                        "series": [
                          {
                            "dataKey": "amount",
                            "label": "利用量"
                          }
                        ]
                      }
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "Chart · line"
                    ]
                  },
                  {
                    "type": "Chart",
                    "props": {
                      "content": {
                        "chartType": "line",
                        "data": [
                          {
                            "month": "1月",
                            "x": 1,
                            "amount": 24,
                            "target": 30,
                            "name": "基本",
                            "share": 45
                          },
                          {
                            "month": "2月",
                            "x": 2,
                            "amount": 42,
                            "target": 38,
                            "name": "追加",
                            "share": 30
                          },
                          {
                            "month": "3月",
                            "x": 3,
                            "amount": 33,
                            "target": 48,
                            "name": "継続",
                            "share": 25
                          }
                        ],
                        "xKey": "month",
                        "valueKey": "amount",
                        "yAxisMin": 0,
                        "yAxisMax": 60,
                        "xAxisLabel": "月",
                        "valueSuffix": " pt",
                        "series": [
                          {
                            "dataKey": "amount",
                            "label": "利用量"
                          }
                        ]
                      }
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "Chart · scatter"
                    ]
                  },
                  {
                    "type": "Chart",
                    "props": {
                      "content": {
                        "chartType": "scatter",
                        "data": [
                          {
                            "month": "1月",
                            "x": 1,
                            "amount": 24,
                            "target": 30,
                            "name": "基本",
                            "share": 45
                          },
                          {
                            "month": "2月",
                            "x": 2,
                            "amount": 42,
                            "target": 38,
                            "name": "追加",
                            "share": 30
                          },
                          {
                            "month": "3月",
                            "x": 3,
                            "amount": 33,
                            "target": 48,
                            "name": "継続",
                            "share": 25
                          }
                        ],
                        "xKey": "x",
                        "valueKey": "amount",
                        "yAxisMin": 0,
                        "yAxisMax": 60,
                        "xAxisLabel": "操作回数",
                        "valueSuffix": " pt",
                        "series": [
                          {
                            "dataKey": "amount",
                            "label": "利用量"
                          }
                        ]
                      }
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "Chart · pie"
                    ]
                  },
                  {
                    "type": "Chart",
                    "props": {
                      "content": {
                        "chartType": "pie",
                        "data": [
                          {
                            "month": "1月",
                            "x": 1,
                            "amount": 24,
                            "target": 30,
                            "name": "基本",
                            "share": 45
                          },
                          {
                            "month": "2月",
                            "x": 2,
                            "amount": 42,
                            "target": 38,
                            "name": "追加",
                            "share": 30
                          },
                          {
                            "month": "3月",
                            "x": 3,
                            "amount": 33,
                            "target": 48,
                            "name": "継続",
                            "share": 25
                          }
                        ],
                        "nameKey": "name",
                        "valueKey": "share",
                        "valueSuffix": "%"
                      }
                    },
                    "children": []
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "地図"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "MapWidgetV2"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "MapWidgetV2"
                    ]
                  },
                  {
                    "type": "MapWidgetV2",
                    "props": {
                      "title": "東京のスポット",
                      "narrative": "座標からネイティブ地図を開きます。",
                      "answer": "2地点を表示",
                      "points": [
                        {
                          "id": "station",
                          "lat": 35.6812,
                          "lng": 139.7671,
                          "title": "東京駅"
                        },
                        {
                          "id": "park",
                          "lat": 35.7148,
                          "lng": 139.7967,
                          "title": "上野公園",
                          "group": "park"
                        }
                      ],
                      "groups": [
                        {
                          "id": "park",
                          "title": "公園"
                        }
                      ],
                      "carousel": true,
                      "minHeight": 180
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "iOSアプリではこのカード内にMapKitの地図を直接表示します。"
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "参照・遷移"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "Link, Entity, Cite, FileCite, CodeCite, MemoryCite, FileNavList, FollowUp"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "Link"
                    ]
                  },
                  {
                    "type": "Link",
                    "props": {
                      "ref": "web",
                      "title": "記事を開く"
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "Entity"
                    ]
                  },
                  {
                    "type": "Entity",
                    "props": {
                      "ref": "web",
                      "value": "サンプル記事",
                      "category": "資料"
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "iOSでは用意した詳細をアプリ内シートで表示。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "Cite"
                    ]
                  },
                  {
                    "type": "Cite",
                    "props": {
                      "refs": [
                        "web",
                        "localFile"
                      ]
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "FileCite"
                    ]
                  },
                  {
                    "type": "FileCite",
                    "props": {
                      "ref": "localFile",
                      "line_range_start": 2,
                      "line_range_end": 3
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "CodeCite"
                    ]
                  },
                  {
                    "type": "CodeCite",
                    "props": {
                      "citation_id": "codeRef",
                      "tool": "コード参照"
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "MemoryCite"
                    ]
                  },
                  {
                    "type": "MemoryCite",
                    "props": {},
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "現行カタログは参照IDを受け取らないため、ブラウザ/アプリとも未解決表示になります。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "FileNavList"
                    ]
                  },
                  {
                    "type": "FileNavList",
                    "props": {
                      "items": [
                        {
                          "ref": "localFile",
                          "title": "仕様メモを表示"
                        },
                        {
                          "ref": "web",
                          "title": "サンプル記事"
                        }
                      ]
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "FollowUp"
                    ]
                  },
                  {
                    "type": "FollowUp",
                    "props": {
                      "value": "この内容を詳しく説明して",
                      "query": "この内容を詳しく説明して"
                    },
                    "children": []
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "iOSではタップ後、Pi経由で新しい会話ターンを送ります。"
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "埋め込み・コード"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "AppBlock, CodeBlock, WritingBlock"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "AppBlock · inline tree"
                    ]
                  },
                  {
                    "type": "AppBlock",
                    "props": {
                      "title": "埋め込みカード",
                      "content": {
                        "type": "card",
                        "props": {
                          "padding": 3,
                          "background": "var(--soft)"
                        },
                        "children": [
                          {
                            "type": "title",
                            "props": {
                              "size": "md"
                            },
                            "children": [
                              "インライン部品"
                            ]
                          },
                          {
                            "type": "text",
                            "props": {},
                            "children": [
                              "文書に含めたノードをその場に描画"
                            ]
                          }
                        ]
                      }
                    },
                    "children": []
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "CodeBlock"
                    ]
                  },
                  {
                    "type": "CodeBlock",
                    "props": {
                      "language": "swift"
                    },
                    "children": [
                      "let greeting = \"こんにちは\"\nprint(greeting)"
                    ]
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "構文ハイライトや実行はありません。editableを付けるとテキスト編集欄。"
                    ]
                  }
                ]
              },
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "WritingBlock"
                    ]
                  },
                  {
                    "type": "WritingBlock",
                    "props": {
                      "subject": "文章ブロック"
                    },
                    "children": [
                      {
                        "type": "text",
                        "props": {},
                        "children": [
                          "見出しと本文をカード型の面にまとめて表示します。"
                        ]
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      },
      {
        "type": "col",
        "props": {
          "gap": 3
        },
        "children": [
          {
            "type": "title",
            "props": {
              "size": "lg"
            },
            "children": [
              "SVG図形"
            ]
          },
          {
            "type": "caption",
            "props": {
              "color": "secondary"
            },
            "children": [
              "svg, g, path, circle, ellipse, rect, line, polyline, polygon, defs, linearGradient, radialGradient, stop, clipPath"
            ]
          },
          {
            "type": "grid",
            "props": {
              "columns": 2,
              "gap": 3
            },
            "children": [
              {
                "type": "card",
                "props": {
                  "padding": 3,
                  "gap": 2
                },
                "children": [
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary",
                      "weight": 700
                    },
                    "children": [
                      "SVG primitive board"
                    ]
                  },
                  {
                    "type": "svg",
                    "props": {
                      "width": "100%",
                      "height": 180,
                      "viewBox": "0 0 560 180"
                    },
                    "children": [
                      {
                        "type": "defs",
                        "props": {},
                        "children": [
                          {
                            "type": "linearGradient",
                            "props": {
                              "id": "sample-gradient",
                              "x1": "0",
                              "y1": "0",
                              "x2": "1",
                              "y2": "1"
                            },
                            "children": [
                              {
                                "type": "stop",
                                "props": {
                                  "offset": "0%",
                                  "stopColor": "#47c7b6"
                                },
                                "children": []
                              },
                              {
                                "type": "stop",
                                "props": {
                                  "offset": "100%",
                                  "stopColor": "#426db7"
                                },
                                "children": []
                              }
                            ]
                          },
                          {
                            "type": "radialGradient",
                            "props": {
                              "id": "sample-radial",
                              "cx": "50%",
                              "cy": "50%",
                              "r": "50%"
                            },
                            "children": [
                              {
                                "type": "stop",
                                "props": {
                                  "offset": "0%",
                                  "stopColor": "#ffe37a"
                                },
                                "children": []
                              },
                              {
                                "type": "stop",
                                "props": {
                                  "offset": "100%",
                                  "stopColor": "#e78755"
                                },
                                "children": []
                              }
                            ]
                          },
                          {
                            "type": "clipPath",
                            "props": {
                              "id": "sample-clip"
                            },
                            "children": [
                              {
                                "type": "circle",
                                "props": {
                                  "cx": 480,
                                  "cy": 65,
                                  "r": 38
                                },
                                "children": []
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "type": "rect",
                        "props": {
                          "x": 8,
                          "y": 12,
                          "width": 100,
                          "height": 62,
                          "rx": 12,
                          "fill": "url(#sample-gradient)"
                        },
                        "children": []
                      },
                      {
                        "type": "text",
                        "props": {
                          "x": 12,
                          "y": 91,
                          "fill": "var(--text)",
                          "fontSize": 11
                        },
                        "children": [
                          "rect + linearGradient"
                        ]
                      },
                      {
                        "type": "g",
                        "props": {
                          "transform": "translate(125 5)"
                        },
                        "children": [
                          {
                            "type": "path",
                            "props": {
                              "d": "M10 65 C25 12 70 12 88 65",
                              "fill": "none",
                              "stroke": "#148d83",
                              "strokeWidth": 5,
                              "strokeLinecap": "round"
                            },
                            "children": []
                          },
                          {
                            "type": "line",
                            "props": {
                              "x1": 8,
                              "y1": 78,
                              "x2": 96,
                              "y2": 78,
                              "stroke": "#60736f",
                              "strokeWidth": 2
                            },
                            "children": []
                          },
                          {
                            "type": "text",
                            "props": {
                              "x": 2,
                              "y": 100,
                              "fill": "var(--text)",
                              "fontSize": 11
                            },
                            "children": [
                              "g + path + line"
                            ]
                          }
                        ]
                      },
                      {
                        "type": "circle",
                        "props": {
                          "cx": 275,
                          "cy": 43,
                          "r": 27,
                          "fill": "#6ca9de"
                        },
                        "children": []
                      },
                      {
                        "type": "ellipse",
                        "props": {
                          "cx": 275,
                          "cy": 92,
                          "rx": 36,
                          "ry": 13,
                          "fill": "#a17bc6"
                        },
                        "children": []
                      },
                      {
                        "type": "text",
                        "props": {
                          "x": 242,
                          "y": 126,
                          "fill": "var(--text)",
                          "fontSize": 11
                        },
                        "children": [
                          "circle + ellipse"
                        ]
                      },
                      {
                        "type": "polyline",
                        "props": {
                          "points": "340,95 360,55 380,76 400,34",
                          "fill": "none",
                          "stroke": "#d07a56",
                          "strokeWidth": 4,
                          "strokeLinejoin": "round"
                        },
                        "children": []
                      },
                      {
                        "type": "polygon",
                        "props": {
                          "points": "355,125 377,96 398,125",
                          "fill": "#dfc25d"
                        },
                        "children": []
                      },
                      {
                        "type": "text",
                        "props": {
                          "x": 340,
                          "y": 148,
                          "fill": "var(--text)",
                          "fontSize": 11
                        },
                        "children": [
                          "polyline + polygon"
                        ]
                      },
                      {
                        "type": "rect",
                        "props": {
                          "x": 442,
                          "y": 27,
                          "width": 78,
                          "height": 78,
                          "fill": "url(#sample-radial)",
                          "clipPath": "url(#sample-clip)"
                        },
                        "children": []
                      },
                      {
                        "type": "text",
                        "props": {
                          "x": 442,
                          "y": 126,
                          "fill": "var(--text)",
                          "fontSize": 11
                        },
                        "children": [
                          "radialGradient + clipPath"
                        ]
                      }
                    ]
                  },
                  {
                    "type": "caption",
                    "props": {
                      "color": "secondary"
                    },
                    "children": [
                      "すべて同じSVGキャンバス内で描画。defs / gradient / stop / clipPathは図形から参照しています。"
                    ]
                  }
                ]
              }
            ]
          }
        ]
      }
    ]
  },
  "state": {
    "name": "Yamabiko",
    "volume": 65,
    "enabled": true,
    "mode": "light",
    "choice": "A",
    "date": "2026-10-12",
    "formStatus": "未送信",
    "status": "操作するとここに状態を表示します。"
  },
  "resources": {
    "mountain": {
      "title": "山と湖",
      "src": "https://images.unsplash.com/photo-1470770841072-f978cf4d019e?auto=format&fit=crop&w=720&q=75",
      "mime": "image/jpeg"
    },
    "coast": {
      "title": "海岸",
      "src": "https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=720&q=75",
      "mime": "image/jpeg"
    },
    "flowerVideo": {
      "title": "Flower video",
      "src": "https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4",
      "mime": "video/mp4"
    },
    "https://example.org": {
      "title": "Example favicon",
      "src": "https://www.apple.com/favicon.ico",
      "mime": "image/x-icon"
    },
    "web": {
      "title": "サンプル記事",
      "url": "https://example.org/article",
      "text": "これは提供済みresourceのサンプル本文です。\n2行目: 引用表示に使われます。\n3行目: 詳細画面に渡されます。"
    },
    "localFile": {
      "title": "仕様メモ.txt",
      "text": "1: 概要\n2: 入力と状態\n3: 表示部品\n4: 制約とフォールバック"
    },
    "codeRef": {
      "title": "Sample.swift",
      "text": "struct Sample {\n    let value = 1\n}"
    }
  }
}
"""#
        let catalogObject = try JSONSerialization.jsonObject(with: Data(catalogJSON.utf8)) as! [String: Any]
        let uiData = try JSONSerialization.data(withJSONObject: catalogObject["ui"]!)
        let stateData = try JSONSerialization.data(withJSONObject: catalogObject["state"]!)
        let resourcesData = try JSONSerialization.data(withJSONObject: catalogObject["resources"]!)
        let ui = try JSONDecoder().decode(GenUINode.self, from: uiData)
        let state = try JSONDecoder().decode([String: JSONValue].self, from: stateData)
        let resources = try JSONDecoder().decode([String: GenUIResource].self, from: resourcesData)
        let document: GenUIDocument
        if ProcessInfo.processInfo.arguments.contains("-GenUIOriginalFixture") {
            document = GenUIOriginalFixture.document
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIReferenceFixture") {
            document = GenUIReferenceFixture.document
        } else if ProcessInfo.processInfo.arguments.contains("-GenUICompactFixture") {
            // Deliberately oversized authored spacing reproduces the broken mobile cards.
            document = GenUIDocument(title: "硬貨の枚数と参照", code: #"""
            const [counts,setCounts]=DIL.useState([0,0,0]);
            const coins=[50,100,500];
            const total=counts.reduce((sum,n)=>sum+n,0);
            return DIL.h('col',{gap:24,padding:12,minHeight:1200,justify:'between'},
              DIL.h('title',{},'硬貨の枚数'),
              DIL.h('caption',{},'枚数を入力すると割合が更新されます'),
              ...coins.map((coin,i)=>DIL.h('row',{gap:20},
                DIL.h('label',{htmlFor:'coin-'+i},coin+'円玉'),
                DIL.h('input',{name:'coin-'+i,inputType:'number',value:counts[i],min:0,onChange:value=>setCounts(old=>old.map((n,j)=>j===i?Math.max(0,Number(value)||0):n))}),
                DIL.h('text',{tabularNums:true},(total?counts[i]/total*100:0).toFixed(1)+'%'))),
              DIL.h('text',{strong:true},'合計 '+total+'枚'),
              DIL.h('col',{gap:32,height:300,justify:'between'},
                DIL.h('title',{},'参照へ移動'),
                DIL.h('text',{},'日本銀行のページで硬貨の種類別データを確認できます。'),
                DIL.h('Link',{title:'日本銀行「通貨流通高」',url:'https://www.boj.or.jp/statistics/money/ryutsu/index.htm'})));
            """#)
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIMarkdownFixture") {
            // Reproduce saved model output that used Text for Markdown prose.
            document = try GenUIDocument.validated(from: #"""
            {"title":"Git worktree","ui":{"type":"col","props":{"gap":3},"children":[
              {"type":"text","props":{"value":"## Git worktree\n1つのリポジトリから複数の作業ディレクトリを用意します。"}},
              {"type":"svg","props":{"viewBox":"0 0 300 70","width":"100%","height":70},"children":[
                {"type":"rect","props":{"x":10,"y":10,"width":280,"height":50,"rx":10,"fill":"#e8eefc"}},
                {"type":"text","props":{"x":150,"y":40,"textAnchor":"middle","fill":"#24336b","value":"共有リポジトリ"}}]},
              {"type":"text","props":{"value":"### 使い方\n```bash\ngit worktree add ../repo-feature -b feature\ncd ../repo-feature\n\n# 作業ツリー一覧\ngit worktree list\n```\n\n**要点:** 各worktreeの作業ファイルは独立しています。"}}
            ]}}
            """#)
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIAuthenticationFixture") {
            document = GenUIDocument(title: "認証の流れ", code: GenUITool.interactiveDiagramExample)
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIPowersFixture") {
            document = GenUIDocument(title: "pow", code: GenUITool.powersExample)
        } else if ProcessInfo.processInfo.arguments.contains("-GenUILineBreakFixture") {
            document = GenUIDocument(title: "ログインの流れ", ui: GenUINode(type: "text", props: [
                "value": .string("① ユーザーがアプリでログイン情報を入力\n↓\n② アプリが認証サーバーに確認を依頼\n↓\n③ 認証サーバーが情報を検証\n↓\n④ 成功ならアプリにトークンを返す\n↓\n⑤ アプリはトークンを使ってAPIにアクセス")
            ]))
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIWorktreeFixture") {
            document = GenUIDocument(title: "Git worktree", code: GenUITool.worktreeDiagramExample)
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIFlowFixture") {
            document = GenUIDocument(title: "PoWを見て、試して理解する", subtitle: "計算の繰り返しで、ブロックの合意をつくる仕組み", code: flowCode,
                                     state: ["simulatorOnly": .bool(ProcessInfo.processInfo.arguments.contains("-GenUISimulatorFixture"))])
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIInlineMapFixture") {
            document = GenUIDocument(title: "東京駅から皇居まで徒歩", code: inlineMapCode)
        } else if ProcessInfo.processInfo.arguments.contains("-GenUIRichStateFixture") {
            document = GenUIDocument(title: "GenUI 状態共有", code: code)
        } else {
            document = GenUIDocument(title: "GenUI 実画面カタログ", subtitle: "iOSアプリの実ランタイムによる表示", ui: ui, state: state, resources: resources)
        }
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        _ = try GenUIDocument.validated(from: json)
        let call = ToolCall(id: "genui-rich-demo", name: GenUITool.name, argumentsJSON: json)
        var payload = ToolActivityPayload()
        payload.apply(ToolActivityEvent(phase: .finished, call: call, result: ToolResult(callId: call.id, name: call.name, content: json), createdAtMs: timestamp))
        try conversations.saveToolActivity(messageId: messageID, variantId: nil, payload: payload)
    }

    static let flowCode = #"""
    const h = DIL.h;
    const [difficulty,setDifficulty] = DIL.useState(4);
    const [sample,setSample] = DIL.useState(null);
    const expected = 2 ** difficulty;
    const change = value => {setDifficulty(Number(value));setSample(null);};
    const experiment = () => {
      let attempts = 1;
      while (attempts < 4096 && Math.random() >= 1 / expected) attempts++;
      setSample(attempts < 4096 ? attempts : '4096回で打ち切り');
    };
    return h('col',{gap:6},
      !state.simulatorOnly && h('title',{},'1. PoWの処理フロー'),
      !state.simulatorOnly && h('card',{padding:3},h('list',{connector:true,marker:'none'},
        h('list-item',{icon:'shuffle',label:'取引データを収集',description:'未承認の取引をブロック候補にまとめる'}),
        h('list-item',{icon:'cpu',iconColor:'info',variant:'outline',label:'Nonceを変えながらハッシュを計算',description:'条件に合うハッシュ値を探索'}),
        h('list-item',{variant:'decision',label:'ハッシュ値が目標値未満？'},
          h('grid',{columns:2,gap:2},
            h('card',{variant:'soft'},h('text',{strong:true},'いいえ'),h('icon',{name:'refresh',color:'secondary'}),h('caption',{},'Nonceを変えて再計算')),
            h('card',{variant:'success'},h('text',{strong:true,color:'success'},'はい'),h('icon',{name:'check',color:'success'}),h('caption',{},'ブロックをネットワークへ送信')))),
        h('list-item',{icon:'blocks',iconColor:'success',label:'他ノードによる検証・チェーンへの追加',description:'有効なチェーンへの採用後、報酬を獲得'})
      )),
      h('title',{},'2. 探索シミュレーター'),
      h('text',{},'難易度を上げると、成功までの平均試行回数が増えます。'),
      h('card',{},
        h('row',{},h('label',{},'難易度'),h('badge',{label:difficulty+' bit'})),
        h('slider',{name:'難易度',min:1,max:10,step:1,value:difficulty,onChange:change,marks:[{value:1,label:'易しい'},{value:10,label:'難しい'}]}),
        h('grid',{columns:2},
          h('card',{variant:'metric'},h('caption',{},'1回の成功確率'),h('text',{},(100/expected).toFixed(2)+'%')),
          h('card',{variant:'metric'},h('caption',{},'平均試行回数'),h('text',{},expected+'回'))),
        h('button',{onClick:experiment},h('icon',{name:'play'}),'探索を試す'),
        sample !== null && h('text',{tabularNums:true},typeof sample==='number'?'今回の試行：'+sample+'回':sample),
        h('caption',{},'成功確率を1/2ⁿとする簡略モデルです。実際のハッシュ計算や実測値ではなく、毎回の結果はランダムに変わります。'),
        h('button',{variant:'outline',onClick:()=>{setDifficulty(4);setSample(null);}},h('icon',{name:'refresh'}),'初期値に戻す'))
    );
    """#

    static let inlineMapCode = #"""
    const h = DIL.h;
    const [visible,setVisible] = DIL.useState(true);
    return h('col',{},
      visible && h('MapWidgetV2',{title:'徒歩ルート（大手門）',minHeight:220,
        origin:{id:'station',title:'東京駅 丸の内中央口',lat:35.6812,lng:139.7659},
        points:[{id:'gate',title:'皇居東御苑 大手門',lat:35.6856,lng:139.7620}],
        narrative:'東京駅と皇居の大手門をチャット内の地図で確認できます。'}),
      h('button',{label:visible?'地図を隠す':'地図を表示',onClick:()=>setVisible(!visible)})
    );
    """#

    static let code = #"""
    const h = DIL.h;
    const [name,setName] = DIL.useState('東京');
    const [mode,setMode] = DIL.useState('light');
    const [volume,setVolume] = DIL.useState(65);
    const [enabled,setEnabled] = DIL.useState(true);
    const chart = DIL.useMemo(() => ({chartType:'bar',xKey:'name',valueSuffix:'%',yAxisMin:0,yAxisMax:100,data:[{name:'現在',value:volume},{name:'目標',value:80}],series:[{dataKey:'value',label:'達成率'}]}),[volume]);
    const reset = () => {setName('東京');setMode('light');setVolume(65);setEnabled(true);};
    return h('col',{gap:5},
      h('row',{justify:'between',align:'center',wrap:true},h('badge',{color:'success',pill:true,label:'状態を共有'}),h('caption',{color:'secondary'},'DIL / LOCAL STATE')),
      h('card',{padding:4,gap:3},
        h('label',{weight:600},'表示する名前'),
        h('input',{name:'name',value:name,placeholder:'名前を入力',onChange:setName}),
        h('segmented-control',{label:'表示モード',value:mode,options:[{label:'ライト',value:'light'},{label:'ダーク',value:'dark'}],onChange:setMode}),
        h('row',{justify:'between'},h('label',{},'slider.value'),h('badge',{label:String(volume),pill:true})),
        h('slider',{name:'volume',value:volume,min:0,max:100,step:1,onChange:setVolume}),
        h('checkbox',{checked:enabled,label:'表示を有効にする',onChange:setEnabled})
      ),
      h('grid',{columns:2,gap:3},
        h('card',{padding:4,theme:mode},h('caption',{color:'secondary'},'現在の名前'),h('title',{size:'xl'},name)),
        h('card',{padding:4,theme:mode},h('caption',{color:'secondary'},'現在の値'),h('title',{size:'xl',tabularNums:true},String(volume)+'%'))
      ),
      h('Chart',{content:chart}),
      h('CodeBlock',{language:'json'},JSON.stringify({name,mode,volume,enabled},null,2)),
      h('row',{gap:3,wrap:true},h('button',{label:'初期値に戻す',onClick:reset}),h('button',{label:'状態をコピー',variant:'secondary',onClick:()=>GenUI.copy(JSON.stringify({name,mode,volume,enabled}))})),
      h('popover',{},h('popover-trigger',{},'補足を表示'),h('popover-content',{showCloseButton:true},h('text',{},'入力とグラフは同じ状態を参照しています。'))),
      h('MapWidgetV2',{title:'東京の地点',points:[{id:'tokyo',lat:35.6812,lng:139.7671,title:'東京駅'}],narrative:'指定した座標をiOSの地図で確認できます。'})
    );
    """#
}
