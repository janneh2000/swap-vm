# STBL_NEW_CODE_TARGET_MATRIX

Generated 2026-09-25T02:43:32.522548+00:00 — window 2026-09-10..2026-09-24 (UTC). Etherscan V2 multichain.

| Target | Chain | Proxy | Current impl | Prior impl | Last upgrade (UTC) | #upg | Class | Verified |
|--------|-------|-------|--------------|-----------|--------------------|------|-------|----------|
| STBL_PT1_Vault-USDY | ETH | `0xd238e964b557bd8f39feba8c2c93d6f428007232` | `0xe211acd0160b5a760ba5c1fbed0c51f53df14249` | `0xcc141662e525d4f1cb5121c5e41711e48ff38e4e` | 2026-02-20T15:17:59+00:00 | 4 | **UNCHANGED** | yes |
| STBL_PT1_YieldDistributor-USDY | ETH | `0x97fb98a7a7400bc651dec6a02640a36f8bdfaa0b` | `0x11ed8072808a1102752f168c77a5155badeaea42` | `-` | 2025-09-27T11:08:23+00:00 | 1 | **UNCHANGED** | yes |
| STBL_LT1_Issuer-USDY | ETH | `0x916442ebaa1cef4b3f5cd9b7a62170b50c3305c1` | `0xf368d517aa9a3efc018a59d6badffa912be1752c` | `0x4384ace58c4b8770a65a20542908405b35d599a9` | 2026-02-20T13:21:35+00:00 | 2 | **UNCHANGED** | yes |
| STBL_LT1_Vault-USDY | ETH | `0x5766b5d21bea4de3dda1b935f1740d194babab1f` | `0x9768fe46b7be507219b3012b8509c0ca4a5d8694` | `0x94a58251d098102661f76662551fc72771fb79bd` | 2026-02-20T15:05:23+00:00 | 4 | **UNCHANGED** | yes |
| STBL_LT1_YieldDistributor-USDY | ETH | `0xcc14f2eddeae2a3c450c7afe328fd7331355dd73` | `0x0438d2f845b133d36f14da6660d3a3edea85550f` | `-` | 2025-09-28T11:32:23+00:00 | 1 | **UNCHANGED** | yes |
| STBL_PT1_Issuer-OUSG | ETH | `0xf8acf255854c8d36010c849f1702eb350c8c4087` | `0xe3632d41040e8b1c7ec7c7b3d8927e53f66e1f17` | `0x1d037fa042da2933d42da8ec6edd3c8dd0d7591c` | 2026-02-20T14:15:23+00:00 | 2 | **UNCHANGED** | yes |
| STBL_PT1_Vault-OUSG | ETH | `0x64bef4478942d8fd62be281707076442aa2d055e` | `0xcfeae702a0d93f0fc39be3d45178969751954f7e` | `0xfc37196aa96b349faf331c32fc33833c2bce3ead` | 2026-02-20T15:15:23+00:00 | 4 | **UNCHANGED** | yes |
| STBL_PT1_YieldDistributor-OUSG | ETH | `0x447a8f3608fb2002c1aa8e44b076b7d62b6fa618` | `0x62fb43e490b3c087661ad8abd97551f916bd6f63` | `-` | 2025-09-28T12:07:59+00:00 | 1 | **UNCHANGED** | yes |
| STBL_LT1_Issuer-OUSG | ETH | `0xbac1f4f20847669ba12841a534b2aa053d65373c` | `0x94ae51951d94800da4a5bd024a1569d05ab6d264` | `0x34e7bc28f648deafcbfcb6e8da1cc0f0af402bde` | 2026-02-20T13:53:35+00:00 | 2 | **UNCHANGED** | yes |
| STBL_LT1_Vault-OUSG | ETH | `0x0437ee84ca723ceb7052a8cc73360e21427c42ea` | `0x9dde30f969e56bcb598124904aefa2583e25a0e1` | `0x7ca0a49a14ee3a495c0e88493039b1771356ea09` | 2026-02-20T15:00:11+00:00 | 5 | **UNCHANGED** | yes |
| STBL_LT1_YieldDistributor-OUSG | ETH | `0x50eda4294d9a57b35a9d836faaeb88d1c4fab6c9` | `0xa6de551fea53b0d0e3e69c8e32343711bb6becfe` | `-` | 2025-09-28T12:15:47+00:00 | 1 | **UNCHANGED** | yes |
| STBL_USST | BSC | `0x1171ce10262a60c17507580a3b70b956f20a35de` | `?` | `-` | ? | 0 | **UNKNOWN** | NO |

## Delta focus

Targets classified NEW or MODIFIED with a last-upgrade timestamp inside the window are the
PRIMARY hunt surface. For MODIFIED targets a prior_impl is present — diff current vs prior:
```
for d in sources/*/ ; do diff -ru "$d/prior" "$d/current" > "diff/$(basename $d).diff" 2>/dev/null; done
```
UNCHANGED/UNKNOWN targets are context only unless they sit on a new cross-contract path.
