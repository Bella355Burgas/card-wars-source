"""Policy and value network for Card Wars.

The board is read as fixed slots (own and opponent lanes, hand, heroes, the card
whose command is running). Each slot holds a card, and a card is embedded from
its text features (cw_data), so the network never meets a card id it has not
been trained on as a number. A choice prompt is embedded by the same card
encoder from its words; the cards left in the own deck and both discard piles
are summed as embeddings.

Every option of a decision (a command, a target, keep or change the hand) is
then scored on its own: its code, lane, side and position, the card it uses,
the slot it is about, and the four cards on its lane (own and opponent's
creature and building) are combined with the state summary. The probability
of an option is a softmax over the legal options only, so there is no fixed
action table and no action mask to keep in sync with the rules.

scripts/ai/policy_agent.gd runs the same forward pass from the exported weights
(export_model.py); check_parity.py checks that both give the same logits.
"""
import torch
import torch.nn as nn
import torch.nn.functional as F

from cw_data import (NUM_SLOTS, DYN_DIM, GLOB_DIM, NUM_CODES, LANE_COUNT, SIDES, OPTION_IDX, POOLS,
                     SLOT_OWN_CREATURE, SLOT_OWN_BUILDING, SLOT_OPP_CREATURE, SLOT_OPP_BUILDING)

# Slots of the four cards on a lane, in the order the candidate features list them.
LANE_SLOTS = (SLOT_OWN_CREATURE, SLOT_OWN_BUILDING, SLOT_OPP_CREATURE, SLOT_OPP_BUILDING)

DEFAULT_DIMS = {"card_dim": 32, "slot_dim": 32, "hidden": 256, "cand_hidden": 64}


class CardWarsPolicy(nn.Module):
    def __init__(self, static_table, card_dim=32, slot_dim=32, hidden=256, cand_hidden=64):
        super().__init__()
        self.dims = {"card_dim": card_dim, "slot_dim": slot_dim, "hidden": hidden, "cand_hidden": cand_hidden}
        self.register_buffer("static", torch.as_tensor(static_table, dtype=torch.float32))
        feat_dim = self.static.shape[1]
        self.card_enc = nn.Sequential(nn.Linear(feat_dim, 64), nn.ReLU(), nn.Linear(64, card_dim))
        self.slot_proj = nn.Linear(card_dim + DYN_DIM, slot_dim)
        state_in = NUM_SLOTS * slot_dim + GLOB_DIM + card_dim + POOLS * card_dim
        self.state_fc = nn.Linear(state_in, hidden)
        self.state_fc2 = nn.Linear(hidden, hidden)
        self.value = nn.Sequential(nn.Linear(hidden, 128), nn.ReLU(), nn.Linear(128, 1))
        cand_in = NUM_CODES + (LANE_COUNT + 1) + SIDES + OPTION_IDX + card_dim + slot_dim * (1 + len(LANE_SLOTS))
        self.cand_state = nn.Linear(hidden, cand_hidden)
        self.cand_feat = nn.Linear(cand_in, cand_hidden, bias=False)
        self.cand_fc = nn.Linear(cand_hidden, cand_hidden)
        self.cand_out = nn.Linear(cand_hidden, 1)

    @classmethod
    def from_checkpoint(cls, ckpt, static_table):
        model = cls(static_table, **ckpt.get("dims", DEFAULT_DIMS))
        model.load_state_dict(ckpt["model"])
        return model

    def forward(self, card_ids, dyn, glob, prompt, pools,
                cand_code, cand_card, cand_lane, cand_slot, cand_side, cand_idx, cand_mask):
        """Returns logits [B, C] for the legal options (padding is -1e9) and values [B]."""
        table = self.card_enc(self.static)                       # [num_ids, card_dim]
        ce = table[card_ids]                                     # [B, slots, card_dim]
        x = F.relu(self.slot_proj(torch.cat([ce, dyn], dim=-1)))  # [B, slots, slot_dim]
        pe = self.card_enc(prompt)                               # [B, card_dim]
        # Sum of the pile's card embeddings, as card counts times the table (row 0 is padding).
        counts = torch.zeros(pools.shape[0], POOLS, table.shape[0], dtype=table.dtype, device=table.device)
        counts.scatter_add_(2, pools, torch.ones(pools.shape, dtype=table.dtype, device=table.device))
        counts[:, :, 0] = 0.0
        pooled = counts @ table                                  # [B, POOLS, card_dim]
        h = F.relu(self.state_fc(torch.cat([x.flatten(1), glob, pe, pooled.flatten(1)], dim=-1)))
        h = F.relu(self.state_fc2(h))

        # Only the real options are scored (the padding of short decisions is skipped).
        B, C = cand_code.shape
        rows, _ = cand_mask.nonzero(as_tuple=True)
        code, card, lane = cand_code[cand_mask], cand_card[cand_mask], cand_lane[cand_mask]
        slot, side, pos = cand_slot[cand_mask], cand_side[cand_mask], cand_idx[cand_mask]
        # Slot features of what an option refers to; index NUM_SLOTS is a zero row.
        x_ext = torch.cat([x, torch.zeros_like(x[:, :1])], dim=1)
        ref = torch.where(slot < 0, torch.full_like(slot, NUM_SLOTS), slot)
        on_lane = lane < LANE_COUNT
        refs = [ref] + [torch.where(on_lane, lane + s, torch.full_like(lane, NUM_SLOTS)) for s in LANE_SLOTS]
        idx = torch.stack(refs, dim=-1)                          # [R, 5]
        picked = x_ext[rows.unsqueeze(-1), idx].flatten(1)       # [R, 5 * slot_dim]
        feat = torch.cat([F.one_hot(code, NUM_CODES).float(),
                          F.one_hot(lane, LANE_COUNT + 1).float(),
                          F.one_hot(side, SIDES).float(),
                          F.one_hot(pos, OPTION_IDX).float(),
                          table[card], picked], dim=-1)

        hid = F.relu(self.cand_state(h)[rows] + self.cand_feat(feat))
        hid = F.relu(self.cand_fc(hid))
        logits = torch.full((B, C), -1e9, dtype=hid.dtype, device=hid.device)
        logits[cand_mask] = self.cand_out(hid).squeeze(-1)
        return logits, self.value(h).squeeze(-1)
