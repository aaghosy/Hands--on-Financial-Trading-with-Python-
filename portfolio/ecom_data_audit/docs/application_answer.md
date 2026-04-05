# Application Answer: "Tell me about a data error others missed"

I found a landed-cost error that looked plausible enough to pass casual review but materially mis-stated margin.

We had a shipment where duty for one SKU was posted as a negative value due to an ingestion mapping issue. It didn't trigger a hard failure because the row was numeric and the total shipment cost still looked "in range" at a glance.

I caught it by adding a control that recomputed landed unit cost from:
1) purchase unit cost (EXW),
2) net received quantity, and
3) allocated freight/duty/broker components.

Then I compared the output to component-level sanity rules (no negative duty/freight, no zero core costs unless explicitly exempted).

Impact:
- Gross margin was overstated for that SKU.
- Reorder decisions would have been biased because the SKU looked more profitable than it actually was.

What I changed:
- Added automated landed-cost validation checks in SQL.
- Added exception exports with source keys and batch lineage.
- Required P1/P2 exceptions to be resolved before final daily finance outputs.

Result:
The team moved from "numbers look close" to auditable, reproducible controls where every metric can be traced back to source records.
