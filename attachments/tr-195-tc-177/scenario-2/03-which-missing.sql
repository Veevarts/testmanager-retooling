-- TC-177 — cual de las siete reservas reportadas no esta en la fuente.
-- Los identificadores ya figuran en el ticket IM-1223; no se expone dato nuevo.
WITH Seven AS (
    SELECT CAST(v AS UNIQUEIDENTIFIER) AS RID, n AS example_no FROM (VALUES
        ('2758E18C-0F18-4A01-ACED-265D3BFCC5D2', 1),
        ('3FBD520F-45CF-4B77-B518-75ECCA16E09A', 2),
        ('24A7D059-BA24-4A57-A7A5-18DB3121EBF4', 3),
        ('E37DE412-85A8-4C8D-B9AF-04AA6C0C5F8B', 4),
        ('E22411F3-25BB-44B7-A65C-6AE894AA598D', 5),
        ('421D2C20-2255-4E28-9E66-1B9D6CA27463', 6),
        ('68152E1B-2EC5-44D6-852A-FAC213BDE8CB', 7)
    ) AS t(v, n)
)
SELECT
    s.example_no,
    CAST(s.RID AS CHAR(36)) AS altru_id,
    CASE WHEN r.ID IS NULL THEN 0 ELSE 1 END AS exists_in_source
FROM Seven s
LEFT JOIN RESERVATION r ON r.ID = s.RID
ORDER BY s.example_no;
