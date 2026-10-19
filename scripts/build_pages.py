#!/usr/bin/env python3
"""
Convert BLOG.md to docs/index.html with Mermaid, KaTeX, and Highlight.js support.
"""
import re
import html

def markdown_to_html(md_text: str) -> str:
    lines = md_text.splitlines()
    out = []
    in_code_block = False
    code_lang = ""
    code_lines = []
    in_table = False
    table_lines = []
    in_ul = False
    in_ol = False

    def close_lists():
        nonlocal in_ul, in_ol
        res = []
        if in_ul:
            res.append("</ul>")
            in_ul = False
        if in_ol:
            res.append("</ol>")
            in_ol = False
        return res

    def format_inline(text: str) -> str:
        # Math is preserved for KaTeX auto-render
        # Bold
        text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
        # Inline code
        text = re.sub(r'`([^`]+)`', lambda m: f'<code>{html.escape(m.group(1))}</code>', text)
        # Markdown links
        text = re.sub(r'\[([^\]]+)\]\(([^)]+)\)', r'<a href="\2">\1</a>', text)
        return text

    def flush_table():
        nonlocal in_table, table_lines
        if not table_lines:
            return []
        res = ['<div class="table-container"><table>']
        header = True
        for row in table_lines:
            cells = [c.strip() for c in row.strip('|').split('|')]
            if all(set(c) <= {'-', ':', ' '} for c in cells):
                header = False
                continue
            res.append('<tr>')
            tag = 'th' if header else 'td'
            for c in cells:
                res.append(f'<{tag}>{format_inline(c)}</{tag}>')
            res.append('</tr>')
        res.append('</table></div>')
        in_table = False
        table_lines = []
        return res

    for line in lines:
        stripped = line.strip()

        # Fenced code block handling
        if stripped.startswith('```'):
            if in_code_block:
                code_content = "\n".join(code_lines)
                if code_lang == 'mermaid':
                    out.append(f'<div class="mermaid">\n{code_content}\n</div>')
                else:
                    lang_class = f'class="language-{code_lang}"' if code_lang else ''
                    escaped = html.escape(code_content)
                    out.append(f'<pre><code {lang_class}>{escaped}</code></pre>')
                in_code_block = False
                code_lines = []
                code_lang = ""
            else:
                out.extend(close_lists())
                if in_table:
                    out.extend(flush_table())
                in_code_block = True
                code_lang = stripped[3:].strip()
                code_lines = []
            continue

        if in_code_block:
            code_lines.append(line)
            continue

        # Tables
        if stripped.startswith('|') and stripped.endswith('|'):
            out.extend(close_lists())
            in_table = True
            table_lines.append(stripped)
            continue
        elif in_table:
            out.extend(flush_table())

        # Empty lines
        if not stripped:
            out.extend(close_lists())
            continue

        # Headings
        if stripped.startswith('# '):
            out.extend(close_lists())
            title = format_inline(stripped[2:])
            out.append(f'<h1 class="post-title">{title}</h1>')
            continue
        elif stripped.startswith('## '):
            out.extend(close_lists())
            h_text = format_inline(stripped[3:])
            slug = re.sub(r'[^a-z0-9]+', '-', stripped[3:].lower()).strip('-')
            out.append(f'<h2 id="{slug}">{h_text}</h2>')
            continue
        elif stripped.startswith('### '):
            out.extend(close_lists())
            h_text = format_inline(stripped[4:])
            slug = re.sub(r'[^a-z0-9]+', '-', stripped[4:].lower()).strip('-')
            out.append(f'<h3 id="{slug}">{h_text}</h3>')
            continue

        # Blockquote
        if stripped.startswith('> '):
            out.extend(close_lists())
            bq_text = format_inline(stripped[2:])
            out.append(f'<blockquote><p>{bq_text}</p></blockquote>')
            continue

        # Horizontal Rule
        if stripped in ('---', '***', '___'):
            out.extend(close_lists())
            out.append('<hr/>')
            continue

        # Unordered list
        if stripped.startswith('- ') or stripped.startswith('* '):
            if in_ol:
                out.append('</ol>')
                in_ol = False
            if not in_ul:
                out.append('<ul>')
                in_ul = True
            item_text = format_inline(stripped[2:])
            out.append(f'<li>{item_text}</li>')
            continue

        # Ordered list
        m_ol = re.match(r'^(\d+)\.\s+(.*)$', stripped)
        if m_ol:
            if in_ul:
                out.append('</ul>')
                in_ul = False
            if not in_ol:
                out.append('<ol>')
                in_ol = True
            item_text = format_inline(m_ol.group(2))
            out.append(f'<li>{item_text}</li>')
            continue

        # Normal paragraph
        out.extend(close_lists())
        out.append(f'<p>{format_inline(line)}</p>')

    out.extend(close_lists())
    if in_table:
        out.extend(flush_table())

    return "\n".join(out)


def build_page():
    with open('BLOG.md', 'r', encoding='utf-8') as f:
        md_text = f.read()

    body_html = markdown_to_html(md_text)

    html_template = f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>From Zero to User-Mode Shell: Building a Formally Specified xv6 in Lean 4</title>
    <meta name="description" content="Formal verification, compile-time paging, process concurrency, and an interactive User Mode shell for MIT xv6-riscv in Lean 4.">
    
    <!-- KaTeX for Math ($W \\oplus X$) -->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.css">
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/katex.min.js"></script>
    <script defer src="https://cdn.jsdelivr.net/npm/katex@0.16.8/dist/contrib/auto-render.min.js"
        onload="renderMathInElement(document.body, {{delimiters: [{{left: '$$', right: '$$', display: true}}, {{left: '$', right: '$', display: false}}]}});"></script>

    <!-- Highlight.js for Syntax Highlighting -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/styles/github-dark-dimmed.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/highlight.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/languages/riscv.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.8.0/languages/lean.min.js"></script>

    <!-- Mermaid.js for Diagrams -->
    <script type="module">
        import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
        mermaid.initialize({{ 
            startOnLoad: true,
            theme: 'dark',
            securityLevel: 'loose'
        }});
    </script>

    <style>
        :root {{
            --bg: #0d1117;
            --surface: #161b22;
            --border: #30363d;
            --text: #c9d1d9;
            --text-muted: #8b949e;
            --accent: #58a6ff;
            --accent-hover: #79c0ff;
            --code-bg: #10141b;
            --font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif;
            --font-mono: ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, "Liberation Mono", monospace;
        }}

        * {{
            box-sizing: border-box;
            margin: 0;
            padding: 0;
        }}

        body {{
            background-color: var(--bg);
            color: var(--text);
            font-family: var(--font-sans);
            line-height: 1.7;
            padding: 2rem 1rem;
            display: flex;
            justify-content: center;
        }}

        .article-container {{
            max-width: 860px;
            width: 100%;
        }}

        .nav-header {{
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding-bottom: 1.5rem;
            margin-bottom: 2rem;
            border-bottom: 1px solid var(--border);
        }}

        .nav-header a {{
            color: var(--accent);
            text-decoration: none;
            font-weight: 500;
            font-size: 0.95rem;
        }}

        .nav-header a:hover {{
            color: var(--accent-hover);
            text-decoration: underline;
        }}

        .post-title {{
            font-size: 2.25rem;
            line-height: 1.25;
            color: #ffffff;
            font-weight: 700;
            margin-bottom: 1rem;
        }}

        h2 {{
            font-size: 1.6rem;
            color: #ffffff;
            margin-top: 2.5rem;
            margin-bottom: 1rem;
            padding-bottom: 0.4rem;
            border-bottom: 1px solid var(--border);
        }}

        h3 {{
            font-size: 1.25rem;
            color: #f0f6fc;
            margin-top: 1.8rem;
            margin-bottom: 0.75rem;
        }}

        p {{
            margin-bottom: 1.2rem;
        }}

        ul, ol {{
            margin-bottom: 1.2rem;
            padding-left: 2rem;
        }}

        li {{
            margin-bottom: 0.4rem;
        }}

        hr {{
            border: 0;
            height: 1px;
            background: var(--border);
            margin: 2.5rem 0;
        }}

        blockquote {{
            border-left: 4px solid var(--accent);
            padding: 0.5rem 1rem;
            background: var(--surface);
            color: var(--text-muted);
            margin: 1.5rem 0;
            border-radius: 0 4px 4px 0;
        }}

        code {{
            font-family: var(--font-mono);
            font-size: 0.9em;
            background-color: var(--code-bg);
            border: 1px solid var(--border);
            padding: 0.15em 0.35em;
            border-radius: 4px;
            color: #79c0ff;
        }}

        pre {{
            margin: 1.2rem 0;
            border-radius: 6px;
            background-color: var(--code-bg);
            border: 1px solid var(--border);
            overflow-x: auto;
            padding: 1rem;
        }}

        pre code {{
            background: transparent;
            border: none;
            padding: 0;
            font-size: 0.88rem;
            color: #e6edf3;
        }}

        .mermaid {{
            background: var(--surface);
            border: 1px solid var(--border);
            border-radius: 6px;
            padding: 1.5rem;
            margin: 1.5rem 0;
            text-align: center;
        }}

        .table-container {{
            overflow-x: auto;
            margin: 1.5rem 0;
        }}

        table {{
            width: 100%;
            border-collapse: collapse;
            font-size: 0.95rem;
        }}

        th, td {{
            padding: 0.75rem 1rem;
            border: 1px solid var(--border);
            text-align: left;
        }}

        th {{
            background: var(--surface);
            color: #ffffff;
            font-weight: 600;
        }}

        tr:nth-child(even) {{
            background-color: rgba(255, 255, 255, 0.02);
        }}

        a {{
            color: var(--accent);
            text-decoration: none;
        }}

        a:hover {{
            text-decoration: underline;
        }}

        footer {{
            margin-top: 4rem;
            padding-top: 1.5rem;
            border-top: 1px solid var(--border);
            text-align: center;
            font-size: 0.9rem;
            color: var(--text-muted);
        }}
    </style>
</head>
<body>
    <article class="article-container">
        <header class="nav-header">
            <div>
                <strong>lean-xv6</strong> | Formally Specified RISC-V Operating System
            </div>
            <div>
                <a href="https://github.com/drhodes/lean-xv6" target="_blank">View on GitHub →</a>
            </div>
        </header>

        {body_html}

        <footer>
            <p>lean-xv6 is an open-source research operating system written in Lean 4.</p>
            <p>© 2026 Derek Rhodes & the lean-xv6 Contributors | Released under the MIT License.</p>
        </footer>
    </article>

    <script>
        document.addEventListener('DOMContentLoaded', (event) => {{
            hljs.highlightAll();
        }});
    </script>
</body>
</html>
"""

    with open('docs/index.html', 'w', encoding='utf-8') as f:
        f.write(html_template)
    print("Successfully built docs/index.html from BLOG.md")

if __name__ == '__main__':
    build_page()
