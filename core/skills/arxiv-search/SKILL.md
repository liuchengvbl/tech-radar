---
name: arxiv-search
description: Search arXiv for academic papers using the arxiv Python library. Use when users want to find research papers, preprints, or academic articles on any topic. Supports filtering by date, category, and author.
allowed-tools: Read,Bash,Write
---

# arXiv Paper Search Skill

Search the arXiv repository for academic papers and preprints.

## Usage

Use the `arxiv` Python library (already installed) directly:

```python
import arxiv

search = arxiv.Search(
    query="SEARCH_TERMS",
    max_results=10,
    sort_by=arxiv.SortCriterion.SubmittedDate
)
for result in arxiv.Client().results(search):
    print(result.published.date(), result.title, result.entry_id)
```

## Query Syntax

arXiv supports field-specific searches:

- `ti:keyword` - Search in title
- `au:name` - Search by author
- `abs:keyword` - Search in abstract
- `cat:category` - Filter by category

### Examples

```python
# General topic search
arxiv.Search(query="novel biosensor", max_results=10, sort_by=arxiv.SortCriterion.SubmittedDate)

# Category-specific search
arxiv.Search(query="cat:eess.SP AND wearable sensor", max_results=10, sort_by=arxiv.SortCriterion.SubmittedDate)

# Combined query
arxiv.Search(query="ti:MEMS AND abs:packaging", max_results=10, sort_by=arxiv.SortCriterion.SubmittedDate)
```

## Output Fields

Each result object has:
- **entry_id**: arXiv URL (e.g., `http://arxiv.org/abs/2604.12345v1`)
- **title**: Paper title
- **authors**: List of author objects
- **summary**: Abstract
- **published**: Publication datetime
- **pdf_url**: Direct PDF link
- **categories**: List of arXiv categories
