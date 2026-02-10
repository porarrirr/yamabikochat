package com.porarri.yamabikochat.utils

import org.junit.Assert.*
import org.junit.Test

/**
 * SvgAnalyzer のユニットテスト
 */
class SvgAnalyzerTest {

    @Test
    fun `analyzeSvg should return valid result for simple SVG`() {
        val simpleSvg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
                <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
            </svg>
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(simpleSvg)
        
        assertTrue("Should be valid SVG", result is SvgAnalysisResult.Valid)
        
        val validResult = result as SvgAnalysisResult.Valid
        assertEquals(100.0, validResult.width)
        assertEquals(100.0, validResult.height)
        assertEquals(1, validResult.elementStats.totalElements)
        assertEquals(1, validResult.elementStats.circleCount)
        assertEquals(SvgComplexity.SIMPLE, validResult.complexity)
        assertTrue(validResult.hasNamespace)
    }

    @Test
    fun `analyzeSvg should return valid result for SVG with viewBox`() {
        val svgWithViewBox = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 150">
                <rect x="10" y="10" width="180" height="130" fill="blue"/>
                <text x="100" y="80" font-family="Arial" font-size="20" fill="white" text-anchor="middle">Hello SVG</text>
            </svg>
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(svgWithViewBox)
        
        assertTrue("Should be valid SVG", result is SvgAnalysisResult.Valid)
        
        val validResult = result as SvgAnalysisResult.Valid
        assertNotNull(validResult.viewBox)
        assertEquals(0.0, validResult.viewBox!!.x, 0.01)
        assertEquals(0.0, validResult.viewBox.y, 0.01)
        assertEquals(200.0, validResult.viewBox.width, 0.01)
        assertEquals(150.0, validResult.viewBox.height, 0.01)
        assertEquals(2, validResult.elementStats.totalElements)
        assertEquals(1, validResult.elementStats.rectCount)
        assertEquals(1, validResult.elementStats.textCount)
    }

    @Test
    fun `analyzeSvg should return valid result for complex SVG`() {
        val complexSvg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="300" height="300">
                <title>Complex SVG Example</title>
                <desc>This is a complex SVG with many elements</desc>
                <g id="shapes">
                    <circle cx="50" cy="50" r="30" fill="red"/>
                    <rect x="100" y="100" width="50" height="50" fill="green"/>
                    <polygon points="200,50 250,150 150,150" fill="blue"/>
                    <path d="M50 200 Q 150 100 250 200" stroke="orange" stroke-width="3" fill="none"/>
                    <line x1="10" y1="250" x2="290" y2="250" stroke="black" stroke-width="2"/>
                    <ellipse cx="150" cy="50" rx="30" ry="20" fill="purple"/>
                </g>
                <use href="#shapes" x="50" y="50" opacity="0.5"/>
                <image href="test.jpg" x="0" y="0" width="100" height="100"/>
            </svg>
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(complexSvg)
        
        assertTrue("Should be valid SVG", result is SvgAnalysisResult.Valid)
        
        val validResult = result as SvgAnalysisResult.Valid
        assertEquals("Complex SVG Example", validResult.title)
        assertEquals("This is a complex SVG with many elements", validResult.description)
        println("elementStats=" + validResult.elementStats)
        println("complexity=" + validResult.complexity)
        assertTrue("Should have many elements", validResult.elementStats.totalElements >= 8)
        assertEquals(1, validResult.elementStats.circleCount)
        assertEquals(1, validResult.elementStats.rectCount)
        assertEquals(1, validResult.elementStats.polygonCount)
        assertEquals(1, validResult.elementStats.pathCount)
        assertEquals(1, validResult.elementStats.lineCount)
        assertEquals(1, validResult.elementStats.ellipseCount)
        assertEquals(1, validResult.elementStats.groupCount)
        assertEquals(1, validResult.elementStats.useCount)
        assertEquals(1, validResult.elementStats.imageCount)
        
        // Complex SVG should have higher complexity
        assertTrue("Should be at least moderate complexity", 
            validResult.complexity in listOf(SvgComplexity.MODERATE, SvgComplexity.COMPLEX, SvgComplexity.VERY_COMPLEX))
    }

    @Test
    fun `analyzeSvg should return invalid result for malformed SVG`() {
        val malformedSvg = """
            <svg xmlns="http://www.w3.org/2000/svg" width="100" height="100">
                <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red" />
            <!-- Missing closing tag -->
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(malformedSvg)
        
        assertTrue("Should be invalid SVG", result is SvgAnalysisResult.Invalid)
    }

    @Test
    fun `analyzeSvg should return invalid result for non-SVG content`() {
        val nonSvgContent = """
            <html>
                <head><title>Not SVG</title></head>
                <body><p>This is not SVG content</p></body>
            </html>
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(nonSvgContent)
        
        assertTrue("Should be invalid", result is SvgAnalysisResult.Invalid)
    }

    @Test
    fun `analyzeSvg should handle SVG without explicit dimensions`() {
        val svgWithoutDimensions = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
                <circle cx="50" cy="50" r="40" fill="blue"/>
            </svg>
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(svgWithoutDimensions)
        
        assertTrue("Should be valid SVG", result is SvgAnalysisResult.Valid)
        
        val validResult = result as SvgAnalysisResult.Valid
        assertNull("Width should be null", validResult.width)
        assertNull("Height should be null", validResult.height)
        assertNotNull("ViewBox should be present", validResult.viewBox)
    }

    @Test
    fun `analyzeSvg should calculate correct element statistics`() {
        val svgWithMultipleShapes = """
            <svg xmlns="http://www.w3.org/2000/svg" width="400" height="400">
                <circle cx="50" cy="50" r="30"/>
                <circle cx="150" cy="50" r="30"/>
                <rect x="50" y="100" width="50" height="50"/>
                <rect x="150" y="100" width="50" height="50"/>
                <rect x="250" y="100" width="50" height="50"/>
                <path d="M50 200 L100 200 L75 150 Z"/>
                <polygon points="150,200 200,200 175,150"/>
                <line x1="250" y1="150" x2="300" y2="200"/>
                <ellipse cx="350" cy="175" rx="25" ry="15"/>
            </svg>
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(svgWithMultipleShapes) as SvgAnalysisResult.Valid
        
        assertEquals(9, result.elementStats.totalElements)
        assertEquals(2, result.elementStats.circleCount)
        assertEquals(3, result.elementStats.rectCount)
        assertEquals(1, result.elementStats.pathCount)
        assertEquals(1, result.elementStats.polygonCount)
        assertEquals(1, result.elementStats.lineCount)
        assertEquals(1, result.elementStats.ellipseCount)
        assertEquals(9, result.elementStats.shapeElements)
        assertTrue("Should be primarily shapes", result.elementStats.isPrimarilyShapes)
    }

    @Test
    fun `complexity calculation should work correctly`() {
        // Simple SVG
        val simpleSvg = "<svg><circle cx='50' cy='50' r='30'/></svg>"
        val simpleResult = SvgAnalyzer.analyzeSvg(simpleSvg) as SvgAnalysisResult.Valid
        assertEquals(SvgComplexity.SIMPLE, simpleResult.complexity)
        
        // More complex SVG with many elements
        val elements = (1..20).joinToString("") { 
            "<circle cx='${it * 10}' cy='${it * 10}' r='5'/>"
        }
        val complexSvg = "<svg>$elements</svg>"
        val complexResult = SvgAnalyzer.analyzeSvg(complexSvg) as SvgAnalysisResult.Valid
        assertTrue("Should be moderate or higher complexity", 
            complexResult.complexity != SvgComplexity.SIMPLE)
    }

    @Test
    fun `viewBox parsing should handle various formats`() {
        val svgWithSpacedViewBox = """
            <svg viewBox=" 10   20   100   200 ">
                <rect x="10" y="20" width="100" height="200"/>
            </svg>
        """.trimIndent()
        
        val result = SvgAnalyzer.analyzeSvg(svgWithSpacedViewBox) as SvgAnalysisResult.Valid
        
        assertNotNull("ViewBox should be parsed", result.viewBox)
        assertEquals(10.0, result.viewBox!!.x, 0.01)
        assertEquals(20.0, result.viewBox.y, 0.01)
        assertEquals(100.0, result.viewBox.width, 0.01)
        assertEquals(200.0, result.viewBox.height, 0.01)
        assertEquals(0.5, result.viewBox.aspectRatio, 0.01)
    }
}