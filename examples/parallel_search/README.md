# Parallel Search MCP

Search the web and fetch page excerpts through RubyLLM::MCP's native streamable
HTTP client using [Parallel Search MCP](https://docs.parallel.ai/integrations/mcp/search-mcp).
The anonymous endpoint is free for light use, with lower rate limits than authenticated
requests. No Parallel API key or model API key is needed for this example.

From a checkout of this repository, with Ruby 3.1.3 or newer and Bundler installed:

```sh
cd examples/parallel_search
bundle install
bundle exec ruby search.rb search "RubyLLM MCP streamable HTTP client"
bundle exec ruby search.rb fetch "https://www.rubyllm-mcp.com/"
```

The script discovers `web_search` and `web_fetch` through `client.tools`, calls the
selected tool directly and prints its response, including source URLs and excerpts.
Use a URL from the search response with `fetch` to read that page. Responses can
include per-page fetch errors; inspect the `errors` field as well as `results`.
Tool or transport errors stop the script; if the free tier is rate limited, wait
before trying again.

This example makes direct tool calls without model inference. It leaves the library's
configuration and other examples unchanged.
