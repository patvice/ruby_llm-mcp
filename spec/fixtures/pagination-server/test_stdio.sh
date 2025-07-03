#!/bin/bash

echo "Testing MCP Pagination Server via stdio..."

# Create a temporary file for MCP commands
cat > mcp_test_commands.json << 'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{"tools":{},"resources":{},"prompts":{}},"clientInfo":{"name":"test-client","version":"1.0.0"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/list","params":{"cursor":"page_2"}}
{"jsonrpc":"2.0","id":4,"method":"resources/list","params":{}}
{"jsonrpc":"2.0","id":5,"method":"resources/list","params":{"cursor":"page_2"}}
{"jsonrpc":"2.0","id":6,"method":"prompts/list","params":{}}
{"jsonrpc":"2.0","id":7,"method":"prompts/list","params":{"cursor":"page_2"}}
{"jsonrpc":"2.0","id":8,"method":"resources/templates/list","params":{}}
{"jsonrpc":"2.0","id":9,"method":"resources/templates/list","params":{"cursor":"page_2"}}
EOF

echo "Sending MCP commands..."
echo

# Send commands to the server
bun src/index.ts --stdio < mcp_test_commands.json | while IFS= read -r line; do
    if [[ $line == *"\"method\":"* ]]; then
        echo ">>> Server response: $line"
    elif [[ $line == *"\"id\":1"* ]]; then
        echo "✅ Initialization: $line"
    elif [[ $line == *"\"id\":2"* ]]; then
        echo "🔧 Tools Page 1: $line"
    elif [[ $line == *"\"id\":3"* ]]; then
        echo "🔧 Tools Page 2: $line"
    elif [[ $line == *"\"id\":4"* ]]; then
        echo "📁 Resources Page 1: $line"
    elif [[ $line == *"\"id\":5"* ]]; then
        echo "📁 Resources Page 2: $line"
    elif [[ $line == *"\"id\":6"* ]]; then
        echo "💬 Prompts Page 1: $line"
    elif [[ $line == *"\"id\":7"* ]]; then
        echo "💬 Prompts Page 2: $line"
    elif [[ $line == *"\"id\":8"* ]]; then
        echo "🔗 Resource Templates Page 1: $line"
    elif [[ $line == *"\"id\":9"* ]]; then
        echo "🔗 Resource Templates Page 2: $line"
    elif [[ -n "$line" ]]; then
        echo "📄 Response: $line"
    fi
done

# Clean up
rm -f mcp_test_commands.json

echo
echo "Test completed!"
