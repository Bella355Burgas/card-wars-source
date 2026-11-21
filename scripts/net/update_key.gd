extends RefCounted
## Public key of the update publisher (tools/update_manifest.gd keygen).
## The updater accepts only manifests signed with its private half.

const PUBLIC_KEY := """-----BEGIN PUBLIC KEY-----
MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA2Mg5m5gLln3d2FV/xmkT
aax71g2aPSr6tvLjs0Cxp+JmW03zZm6/WG/zA4hA1aUnEm2NHlcW1wJt/JRaGuZp
pEDg3OfAYz99EHLIOgLviTisoBUFalHOzVQodtSVpC8/T2bL+S/nB0RH27/+Iow2
43PgDJW7QC2WaQrl01tzAeqohMws+mACxmYuZTYV1bj3feqA/2OdJLj86p8h66ip
0b/N9idz1oyz100OaB6LZsmkPiE9wxa7NKj/qTIQbB3K8Vfl/uWQkrxNfEP5XJlJ
0Ee1UnQMYN4k/uXzDG4w/tjR8vxgtblXD1cELAHNa3zewJra+tMOG8JbgwZhSnYY
Ov0fe36BPnye2dBRJvrzvxAZE89Z5nLqyl7ppeLQ4e7zHp5FxeBXo4MWksQiFLMc
HooOBOWZFYz2u4rrZ3oblc5926V+wVw4WCQ4r2UFC+pqicYfCLfDs6ZHbhJj/NZf
hFN8AZKdWd3oytOr1NWNg8nOHk/I/0TbFJtV3QIQ1fudAgMBAAE=
-----END PUBLIC KEY-----"""
