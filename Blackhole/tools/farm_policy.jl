module ScienceFarmPolicy
# Excluded by the user (Bosgame 2026-10-24, Desktop 2026-10-25); re-enable only
# on explicit request.
const excluded = ["Bosgame", "sim-bosgame", "Desktop"]
allowed(name) = all(excluded) do blocked
    n=lowercase(name); b=lowercase(blocked)
    n!=b && !startswith(n,b*" (") && !startswith(n,b*" ·")
end
end
