package com.porarri.yamabikochat.utils

import com.porarri.yamabikochat.data.models.CodeBlock
import com.porarri.yamabikochat.data.models.GroupType
import org.junit.Assert.*
import org.junit.Test

/**
 * CodeExtractorUtils のユニットテスト
 */
class CodeExtractorUtilsTest {

    @Test
    fun `extractCodeBlocks should detect markdown code blocks`() {
        val markdown = """
            Normal text here.
            
            ```python
            def hello():
                print("Hello!")
            ```
            
            More normal text.
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(markdown)
        
        assertEquals(1, result.size)
        assertEquals("python", result[0].language)
        assertEquals("markdown", result[0].extractionMethod)
        assertTrue(result[0].content.contains("def hello():"))
        assertTrue(result[0].filename.endsWith(".py"))
    }

    @Test
    fun `extractCodeBlocks should detect custom tag code blocks`() {
        val markdown = """
            Some text here.
            
            <code_start:javascript>
            function greet(name) {
                console.log("Hello " + name);
            }
            <code_end:javascript>
            
            End text.
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(markdown)
        
        assertEquals(1, result.size)
        assertEquals("javascript", result[0].language)
        assertEquals("custom_tag", result[0].extractionMethod)
        assertTrue(result[0].content.contains("function greet"))
        assertTrue(result[0].filename.endsWith(".js"))
    }

    @Test
    fun `extractCodeBlocks should detect multiple code blocks`() {
        val markdown = """
            Text with multiple code blocks.
            
            ```python
            print("Python code")
            ```
            
            And another one:
            
            <code_start:kotlin>
            fun main() {
                println("Kotlin code")
            }
            <code_end:kotlin>
            
            End.
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(markdown)
        
        assertEquals(2, result.size)
        assertEquals("python", result[0].language)
        assertEquals("kotlin", result[1].language)
    }

    @Test
    fun `containsCodeBlocks should return true for markdown with code`() {
        val markdownWithCode = "Normal text ```python\nprint('hello')\n```"
        val markdownWithoutCode = "Just normal text here"
        
        assertTrue(CodeExtractorUtils.containsCodeBlocks(markdownWithCode))
        assertFalse(CodeExtractorUtils.containsCodeBlocks(markdownWithoutCode))
    }

    @Test
    fun `containsCodeBlocks should return true for custom tags`() {
        val markdownWithCustomTag = "Text <code_start:java>\nSystem.out.println();\n<code_end:java>"
        
        assertTrue(CodeExtractorUtils.containsCodeBlocks(markdownWithCustomTag))
    }

    @Test
    fun `isSupportedLanguage should return correct results`() {
        assertTrue(CodeExtractorUtils.isSupportedLanguage("python"))
        assertTrue(CodeExtractorUtils.isSupportedLanguage("kotlin"))
        assertTrue(CodeExtractorUtils.isSupportedLanguage("javascript"))
        assertFalse(CodeExtractorUtils.isSupportedLanguage("unknown"))
    }

    @Test
    fun `getFileExtension should return correct extensions`() {
        assertEquals("py", CodeExtractorUtils.getFileExtension("python"))
        assertEquals("kt", CodeExtractorUtils.getFileExtension("kotlin"))
        assertEquals("js", CodeExtractorUtils.getFileExtension("javascript"))
        assertEquals("html", CodeExtractorUtils.getFileExtension("html"))
        assertEquals("txt", CodeExtractorUtils.getFileExtension("unknown"))
    }

    @Test
    fun `extractCodeBlocks should handle empty content correctly`() {
        val emptyMarkdown = ""
        val result = CodeExtractorUtils.extractCodeBlocks(emptyMarkdown)
        assertTrue(result.isEmpty())
    }

    @Test
    fun `extractCodeBlocks should handle malformed code blocks`() {
        val malformedMarkdown = """
            ```python
            # Missing closing backticks
            
            <code_start:java>
            // Missing end tag
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(malformedMarkdown)
        // Should not extract malformed blocks
        assertTrue(result.isEmpty())
    }

    @Test
    fun `extractCodeBlocks should detect SVG content`() {
        val markdownWithSvg = """
            ここにSVGがあります：
            
            ```svg
            <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
                <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
            </svg>
            ```
            
            以上です。
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(markdownWithSvg)
        
        assertEquals(1, result.size)
        assertEquals("svg", result[0].language)
        assertTrue(result[0].isSvg)
        assertTrue(result[0].content.contains("<svg"))
        assertTrue(result[0].content.contains("</svg>"))
        assertTrue(result[0].filename.endsWith(".svg"))
    }

    @Test
    fun `extractCodeBlocks should detect inline SVG`() {
        val textWithInlineSvg = """
            以下はインラインSVGの例です：
            
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
                <rect x="10" y="10" width="80" height="80" fill="blue"/>
            </svg>
            
            これで終わりです。
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(textWithInlineSvg)
        
        assertEquals(1, result.size)
        assertEquals("svg", result[0].language)
        assertEquals("inline_svg", result[0].extractionMethod)
        assertTrue(result[0].content.contains("viewBox"))
    }

    @Test
    fun `extractCodeBlocks should detect custom tag SVG`() {
        val customTagSvg = """
            SVGの例：
            
            <code_start:svg>
            <svg width="200" height="200">
                <polygon points="100,10 40,198 190,78 10,78 160,198" 
                         style="fill:lime;stroke:purple;stroke-width:5;fill-rule:evenodd;" />
            </svg>
            <code_end:svg>
            
            終了。
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(customTagSvg)
        
        assertEquals(1, result.size)
        assertEquals("svg", result[0].language)
        assertEquals("custom_tag", result[0].extractionMethod)
        assertTrue(result[0].content.contains("polygon"))
    }

    @Test
    fun `SVG should be detected from XML code blocks`() {
        val xmlWithSvg = """
            ```xml
            <svg xmlns="http://www.w3.org/2000/svg" width="50" height="50">
                <path d="M25,5 L45,40 L5,40 Z" fill="green"/>
            </svg>
            ```
        """.trimIndent()
        
        val result = CodeExtractorUtils.extractCodeBlocks(xmlWithSvg)
        
        assertEquals(1, result.size)
        // Should be converted to svg language due to content analysis
        assertEquals("svg", result[0].language)
        assertTrue(result[0].content.contains("<path"))
    }

    @Test
    fun `HTML with nested SVG should stay html`() {
        val htmlWithSvg = """
            ```html
            <!DOCTYPE html>
            <html lang="ja">
            <head>
            <title>解説 2008 物理</title>
            </head>
            <body>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
                <circle cx="5" cy="5" r="4" />
            </svg>
            </body>
            </html>
            ```
        """.trimIndent()

        val result = CodeExtractorUtils.extractCodeBlocks(htmlWithSvg)

        assertEquals(1, result.size)
        assertEquals("html", result[0].language)
        assertFalse(result[0].isSvg)
        assertTrue(result[0].content.contains("<svg"))
        assertTrue(result[0].filename.endsWith(".html"))
    }

    @Test
    fun `HTML document labeled as svg should be treated as html`() {
        val htmlLabeledSvg = """
            ```svg
            <!DOCTYPE html>
            <html lang="ja">
            <head>
            <meta charset="UTF-8">
            <title>【解説】2008 甲南大 物理 (一部)- 電気力線と電場</title>
            </head>
            <body>
            <p>ると、</p>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20">
                <text x="0" y="15">4\pi k_0 q</text>
            </svg>
            </body>
            </html>
            ```
        """.trimIndent()

        val result = CodeExtractorUtils.extractCodeBlocks(htmlLabeledSvg)

        assertEquals(1, result.size)
        assertEquals("html", result[0].language)
        assertFalse(result[0].isSvg)
        assertTrue(result[0].filename.endsWith(".html"))
    }

    @Test
    fun `unlabeled HTML document should be treated as html`() {
        val unlabeledHtml = """
            ```
            <!DOCTYPE html>
            <html>
            <head><title>Page</title></head>
            <body><p>hello</p></body>
            </html>
            ```
        """.trimIndent()

        val result = CodeExtractorUtils.extractCodeBlocks(unlabeledHtml)

        assertEquals(1, result.size)
        assertEquals("html", result[0].language)
        assertTrue(result[0].isHtml)
        assertFalse(result[0].isSvg)
        assertTrue(result[0].filename.endsWith(".html"))
    }

    @Test
    fun `inline SVG inside unfenced HTML document should not be extracted`() {
        val htmlDocument = """
            <!DOCTYPE html>
            <html>
            <head><title>2008 physics</title></head>
            <body>
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
                <rect width="10" height="10" />
            </svg>
            </body>
            </html>
        """.trimIndent()

        val result = CodeExtractorUtils.extractCodeBlocks(htmlDocument)

        assertTrue(result.none { it.isSvg })
    }

    @Test
    fun `inline SVG after closed HTML document should still be extracted`() {
        val text = """
            <html><body><p>page</p></body></html>
            <svg viewBox="0 0 10 10"><rect width="10" height="10" /></svg>
        """.trimIndent()

        val result = CodeExtractorUtils.extractCodeBlocks(text)

        assertEquals(1, result.size)
        assertEquals("svg", result[0].language)
        assertEquals("inline_svg", result[0].extractionMethod)
    }

    @Test
    fun `SVG with XML declaration should still be promoted from xml`() {
        val xmlWithSvg = """
            ```xml
            <?xml version="1.0" encoding="UTF-8"?>
            <!-- icon -->
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
                <circle cx="5" cy="5" r="4" />
            </svg>
            ```
        """.trimIndent()

        val result = CodeExtractorUtils.extractCodeBlocks(xmlWithSvg)

        assertEquals(1, result.size)
        assertEquals("svg", result[0].language)
        assertTrue(result[0].isSvg)
    }

    @Test
    fun `getCodeBlockStats should return correct statistics`() {
        val codeBlocks = listOf(
            CodeBlock(
                language = "python",
                content = "line1\nline2\nline3",
                startIndex = 0,
                endIndex = 10,
                extractionMethod = "markdown",
                filename = "test.py"
            ),
            CodeBlock(
                language = "javascript",
                content = "console.log('hello');",
                startIndex = 20,
                endIndex = 30,
                extractionMethod = "custom_tag",
                filename = "test.js"
            ),
            CodeBlock(
                language = "svg",
                content = "<svg><circle cx=\"50\" cy=\"50\" r=\"40\"/></svg>",
                startIndex = 40,
                endIndex = 50,
                extractionMethod = "markdown",
                filename = "circle.svg"
            )
        )
        
        val stats = CodeExtractorUtils.getCodeBlockStats(codeBlocks)
        
        assertEquals(3, stats.totalBlocks)
        assertEquals(3, stats.languageCount)
        assertEquals(5, stats.totalLines) // 3 + 1 + 1 lines
        assertEquals(1, stats.languageDistribution["python"])
        assertEquals(1, stats.languageDistribution["javascript"])
        assertEquals(1, stats.languageDistribution["svg"])
    }
    
    @Test
    fun `groupCodeBlocks should create web bundle for related HTML CSS JS`() {
        val codeBlocks = listOf(
            CodeBlock(
                language = "html",
                content = "<html><head></head><body><h1>Test</h1></body></html>",
                startIndex = 0,
                endIndex = 50,
                extractionMethod = "markdown",
                filename = "test.html"
            ),
            CodeBlock(
                language = "css",
                content = "body { background-color: red; }",
                startIndex = 100,
                endIndex = 150,
                extractionMethod = "markdown",
                filename = "styles.css"
            ),
            CodeBlock(
                language = "js",
                content = "console.log('Hello World');",
                startIndex = 200,
                endIndex = 250,
                extractionMethod = "markdown",
                filename = "script.js"
            )
        )
        
        val groups = CodeExtractorUtils.groupCodeBlocks(codeBlocks)
        
        assertEquals(1, groups.size)
        assertEquals(GroupType.WEB_BUNDLE, groups[0].groupType)
        assertEquals(3, groups[0].blocks.size)
        assertTrue(groups[0].canIntegrate)
        
        val htmlBlock = groups[0].htmlBlock
        assertNotNull(htmlBlock)
        assertEquals("html", htmlBlock!!.language)
        
        assertEquals(1, groups[0].cssBlocks.size)
        assertEquals(1, groups[0].jsBlocks.size)
    }
    
    @Test
    fun `groupCodeBlocks should create single groups when blocks are too far apart`() {
        val codeBlocks = listOf(
            CodeBlock(
                language = "html",
                content = "<html></html>",
                startIndex = 0,
                endIndex = 20,
                extractionMethod = "markdown",
                filename = "test.html"
            ),
            CodeBlock(
                language = "css",
                content = "body { color: blue; }",
                startIndex = 1000, // Too far from HTML
                endIndex = 1050,
                extractionMethod = "markdown",
                filename = "styles.css"
            )
        )
        
        val groups = CodeExtractorUtils.groupCodeBlocks(codeBlocks)
        
        assertEquals(2, groups.size)
        groups.forEach { group ->
            assertEquals(GroupType.SINGLE, group.groupType)
            assertEquals(1, group.blocks.size)
            assertFalse(group.canIntegrate)
        }
    }
    
    @Test
    fun `groupCodeBlocks should handle HTML only blocks`() {
        val codeBlocks = listOf(
            CodeBlock(
                language = "html",
                content = "<html><body><p>Hello</p></body></html>",
                startIndex = 0,
                endIndex = 40,
                extractionMethod = "markdown",
                filename = "page.html"
            )
        )
        
        val groups = CodeExtractorUtils.groupCodeBlocks(codeBlocks)
        
        assertEquals(1, groups.size)
        assertEquals(GroupType.SINGLE, groups[0].groupType)
        assertEquals(1, groups[0].blocks.size)
        assertFalse(groups[0].canIntegrate) // HTML only cannot integrate
    }
    
    @Test
    fun `groupCodeBlocks should handle non-web related blocks`() {
        val codeBlocks = listOf(
            CodeBlock(
                language = "python",
                content = "print('hello')",
                startIndex = 0,
                endIndex = 20,
                extractionMethod = "markdown",
                filename = "script.py"
            ),
            CodeBlock(
                language = "java",
                content = "System.out.println('world');",
                startIndex = 30,
                endIndex = 60,
                extractionMethod = "markdown",
                filename = "Main.java"
            )
        )
        
        val groups = CodeExtractorUtils.groupCodeBlocks(codeBlocks)
        
        assertEquals(2, groups.size)
        groups.forEach { group ->
            assertEquals(GroupType.SINGLE, group.groupType)
            assertEquals(1, group.blocks.size)
            assertFalse(group.canIntegrate)
        }
    }
    
    @Test
    fun `containsWebBundle should detect HTML with CSS and JS`() {
        val textWithWebBundle = """
            Here's a complete web page:
            
            ```html
            <html>
                <body><h1>Hello</h1></body>
            </html>
            ```
            
            With some styling:
            
            ```css
            h1 { color: blue; }
            ```
            
            And some JavaScript:
            
            ```js
            alert('Hello World');
            ```
        """.trimIndent()
        
        assertTrue(CodeExtractorUtils.containsWebBundle(textWithWebBundle))
    }
    
    @Test
    fun `containsWebBundle should return false for single language`() {
        val htmlOnly = """
            ```html
            <html><body><h1>Test</h1></body></html>
            ```
        """.trimIndent()
        
        val jsOnly = """
            ```js
            console.log('test');
            ```
        """.trimIndent()
        
        assertFalse(CodeExtractorUtils.containsWebBundle(htmlOnly))
        assertFalse(CodeExtractorUtils.containsWebBundle(jsOnly))
    }
    
    @Test
    fun `containsWebBundle should detect inline HTML with style tags`() {
        val textWithInlineStyles = """
            Here's HTML with inline styles:
            <html>
                <head>
                    <style>body { margin: 0; }</style>
                </head>
                <body>
                    <script>console.log('test');</script>
                </body>
            </html>
        """.trimIndent()
        
        assertTrue(CodeExtractorUtils.containsWebBundle(textWithInlineStyles))
    }
    
    @Test
    fun `groupCodeBlocks should sort blocks by start index`() {
        val codeBlocks = listOf(
            CodeBlock(
                language = "js",
                content = "console.log('second');",
                startIndex = 200,
                endIndex = 250,
                extractionMethod = "markdown",
                filename = "script.js"
            ),
            CodeBlock(
                language = "html",
                content = "<html></html>",
                startIndex = 0,
                endIndex = 50,
                extractionMethod = "markdown",
                filename = "test.html"
            ),
            CodeBlock(
                language = "css",
                content = "body { color: red; }",
                startIndex = 100,
                endIndex = 150,
                extractionMethod = "markdown",
                filename = "styles.css"
            )
        )
        
        val groups = CodeExtractorUtils.groupCodeBlocks(codeBlocks)
        
        assertEquals(1, groups.size)
        assertEquals(GroupType.WEB_BUNDLE, groups[0].groupType)
        
        // Blocks should be sorted by startIndex within the group
        val sortedBlocks = groups[0].blocks
        for (i in 0 until sortedBlocks.size - 1) {
            assertTrue(sortedBlocks[i].startIndex <= sortedBlocks[i + 1].startIndex)
        }
    }
    
    @Test
    fun `empty groupCodeBlocks should return empty list`() {
        val emptyList = emptyList<CodeBlock>()
        val groups = CodeExtractorUtils.groupCodeBlocks(emptyList)
        
        assertTrue(groups.isEmpty())
    }
}