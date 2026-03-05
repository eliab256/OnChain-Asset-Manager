factory:

- gestire grantRole che viene ereditato da factory a tutti gli index (forse non serve perchè role in index è della factory)
- check CEI pattern

index

- fare check se getPrice viene chiamato più volte nella stessa tx inutilmente
- sostituire codice con internal function nei calcoli di initialize
- vedere se c'è un pattern più efficiente per gestire swap e transfer
- check CEI pattern, agg nonReentrant

router

- check CEI pattern

creare contratto timelock
