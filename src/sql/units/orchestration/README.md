# Orchestration

Publishes the executive summary and its report from the four upstream gold marts.
The reporting anchor is `2025-12-31`. The `drop` job parameter follows the unit
interface; upstream jobs select the data snapshot before this job runs.

Redshift decimal AVG preserves the input scale (2). For division, the initial
scale is `max(4, s1 + p2 - s2 + 1)` and precision is
`p1 - s1 + s2 + scale`; precision above 38 reduces scale, with a minimum of 4.
The return ratio divides two `(14,4)` operands, yielding `(29,15)` before
multiplication by 100. The shipping numerator sums `(10,2) * BIGINT` to `(38,2)`;
division by BIGINT `(19,0)` reduces the result to `(38,4)`.
Non-negative results are floored at those scales before final casts.
