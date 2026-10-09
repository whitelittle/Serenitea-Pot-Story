"""把 .docx 按文档顺序转成 Markdown（标题 + 段落 + 表格）。

用法: python docx_to_md.py <input.docx> <output.md> <标题>
只用 python-docx，不引入其它依赖。
"""
import sys
from docx import Document
from docx.table import Table
from docx.text.paragraph import Paragraph
from docx.oxml.ns import qn


def iter_block_items(parent):
    body = parent.element.body
    for child in body.iterchildren():
        if child.tag == qn('w:p'):
            yield Paragraph(child, parent)
        elif child.tag == qn('w:tbl'):
            yield Table(child, parent)


def clean(text):
    return " ".join((text or "").replace("\u00a0", " ").split())


def heading_level(style_name):
    name = (style_name or "").strip().lower()
    if name in ("title", "标题"):
        return 1
    for prefix in ("heading ", "标题 "):
        if name.startswith(prefix):
            tail = name[len(prefix):].strip()
            if tail.isdigit():
                return max(1, min(6, int(tail) + 1))
    return None


def table_to_md(table):
    rows = []
    for row in table.rows:
        cells = []
        for cell in row.cells:
            text = clean(" ".join(p.text for p in cell.paragraphs))
            cells.append(text.replace("|", "\\|") or " ")
        rows.append(cells)
    if not rows:
        return []
    width = max(len(r) for r in rows)
    rows = [r + [" "] * (width - len(r)) for r in rows]
    out = ["| " + " | ".join(rows[0]) + " |",
           "|" + "|".join([" --- "] * width) + "|"]
    for r in rows[1:]:
        out.append("| " + " | ".join(r) + " |")
    return out


def main(src, dst, title):
    doc = Document(src)
    lines = [f"# {title}", "",
             "> 本文件由 `docs/` 下的同名 `.docx` 自动转换生成（python-docx，按文档顺序保留标题、段落与表格），",
             "> 便于在 GitHub 上直接阅读与给 AI 摄取。**原始 `.docx` 为准**，两者内容不一致时以 docx 为权威。", ""]
    for block in iter_block_items(doc):
        if isinstance(block, Paragraph):
            text = clean(block.text)
            if not text:
                continue
            level = heading_level(block.style.name if block.style else "")
            if level:
                lines.append("")
                lines.append("#" * min(6, level) + " " + text)
                lines.append("")
            else:
                lines.append(text)
                lines.append("")
        else:
            md = table_to_md(block)
            if md:
                lines.append("")
                lines.extend(md)
                lines.append("")
    text = "\n".join(lines).rstrip() + "\n"
    with open(dst, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print(f"{dst}: {len(text)} chars, {text.count(chr(10))} lines")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2], sys.argv[3])
