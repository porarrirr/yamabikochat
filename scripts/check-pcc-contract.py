#!/usr/bin/env python3
"""Verify the native PCC contract against Apple's published API documentation.

No provider metadata is inferred from npm names, URLs or model names. New Apple
routing/usage fields require an explicit review of the adapter and Pi patch.
"""
import concurrent.futures
import urllib.request

ROOT = 'https://developer.apple.com/documentation/foundationmodels/'
CONTRACT = {
    'privatecloudcomputelanguagemodel.md': ['PrivateCloudComputeLanguageModel', 'contextSize', 'quotaUsage', 'availability'],
    'languagemodelsession/usage-swift.struct/input-swift.struct.md': ['totalTokenCount', 'cachedTokenCount'],
    'languagemodelsession/usage-swift.struct/output-swift.struct.md': ['totalTokenCount', 'reasoningTokenCount'],
    'generationoptions/maximumresponsetokens.md': ['without throwing an error', 'longest answer', 'context size'],
    'adding-server-side-intelligence-with-private-cloud-compute.md': ['.light', '.moderate', '.deep', 'quotaLimitReached'],
    'tool.md': ['call(arguments:)', 'GenerationSchema', 'PromptRepresentable', 'concurrently'],
    'dynamicgenerationschema.md': ['DynamicGenerationSchema', 'Property'],
    'dynamicgenerationschema/property.md': ['schema: DynamicGenerationSchema', 'isOptional: Bool'],
    'generatedcontent.md': ['isComplete', 'jsonString'],
    'transcript.md': ['ToolCall', 'ToolOutput', 'Encodable', 'Decodable'],
    'analyzing-images-with-multimodal-prompting.md': ['PrivateCloudComputeLanguageModel', 'Attachment'],
}

def verify(item):
    path, expected = item
    with urllib.request.urlopen(ROOT + path, timeout=30) as response:
        content = response.read().decode('utf-8')
    missing = [value for value in expected if value not in content]
    if missing:
        raise RuntimeError(f'PCC upstream contract drift in {path}: missing {missing}')
    return path

if __name__ == '__main__':
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        for path in executor.map(verify, CONTRACT.items()):
            print('PCC contract verified:', path)
