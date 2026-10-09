# tools/

纯 Python 脚本，只处理文本；不依赖千星编辑器。

## docx_to_md.py

把 .docx 按文档顺序转成 Markdown（标题、段落、表格），用于让 GitHub 可直接阅读、让 AI 可摄取。

```
python docx_to_md.py <input.docx> <output.md> <标题>
```

依赖：python-docx。转换产物以原始 .docx 为准；仓库内 docs/*.md 就是这么生成的。