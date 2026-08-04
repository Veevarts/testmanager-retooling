/**
 * Install ordering for the Veevart package set (IM-741).
 *
 * The package LIST is never mirrored here — it is fetched fresh from the
 * DevOps registry (`GET /packages` on `sf-package-pusher`) on every run. What
 * lives here is the one thing the registry cannot tell us: **dependency
 * order**. The service states outright that it does not orchestrate
 * dependencies (`openapi.yaml` §description), and registry rows carry no
 * `dependsOn`, so ordering is the consumer's job.
 *
 * This is expressed as a RULE over the dependency roots, not as a catalog:
 *
 *   Tier 0  `Auctifera`, `NPSP`                     — depend on nothing.
 *   Tier 1  `VNFP`                                  — depends on both tier-0.
 *   Tier 2  `Veevart Data Model`, `Veevart Reporting` — the product packages
 *                                                      build on these.
 *   Tier 3  everything else                         — depends on the above.
 *
 * Only the roots are named. Any package DevOps adds to the registry falls into
 * the last tier automatically, so the rule stays correct as the registry grows
 * without this file having to know about it.
 *
 * Why a rule at all: `GetPackages` sorts by `name.localeCompare(name)`, and
 * that collation compares case-insensitively on the primary strength — so
 * `Veevart …` sorts BEFORE `VNFP` and VNFP lands dead last, after the five
 * packages that depend on it. (A plain ASCII sort would have been correct by
 * accident, `N` < `e`; relying on that would be a latent trap.)
 *
 * The same trap caught `VeevartDataModel`, which is why it is now named here.
 * It has NO SPACE, so `localeCompare` puts it AFTER `Veevart Ticketing` — the
 * package that depends on it. A prod run proved it: "Veevart Ticketing: Invalid
 * Upgrade. The package you're installing depends on package 'Veevart Data
 * Model', version '0.1'."
 *
 * Its placement is evidence-based rather than assumed. In that same run
 * Auctifera, VNFP, Accounting, Forms, Payments and Rentals & Groups all
 * installed successfully BEFORE Ticketing failed, so none of them needs the
 * data model — it belongs after VNFP, not among the tier-0 foundations.
 *
 * TODO(IM-741): once the registry exposes `installOrder` / `dependsOn`,
 * ordering becomes data and this policy collapses into a sort on that field.
 * Three separate prod failures have now been dependency-order problems this
 * rule had to be taught by hand.
 */

/** Packages with no dependencies. Installed first, in the order listed. */
const TIER_0_FOUNDATIONS: readonly string[] = ['Auctifera', 'NPSP'];

/** Depends on every tier-0 package; everything else depends on it. */
const TIER_1_CORE: readonly string[] = ['VNFP'];

/**
 * Platform packages the product packages build on. Installed after VNFP (which
 * demonstrably does not need either) and before everything else. Neither is in
 * the DevOps registry — both are pinned in `shared/domain/pinned-veevart-packages.ts`.
 */
const TIER_2_PLATFORM: readonly string[] = [
    'Veevart Data Model',
    'Veevart Reporting',
];

const KNOWN_TIERS: readonly (readonly string[])[] = [
    TIER_0_FOUNDATIONS,
    TIER_1_CORE,
    TIER_2_PLATFORM,
];

/**
 * Compare registry names ignoring spacing and case.
 *
 * The registry calls it `VeevartDataModel`; Salesforce's own error calls the
 * same package `Veevart Data Model`. Since the prd row for it does not exist
 * yet, we cannot know which spelling DevOps will publish — and an exact-match
 * rule that silently fails to recognise a root would put it back in the last
 * tier, reproducing the very bug this fixes with no signal.
 */
const normalizeName = (name: string): string =>
    name.replace(/\s+/g, '').toLowerCase();

/**
 * Sort registry package names into dependency-safe install order.
 *
 * Pure and total: duplicates collapse to one entry, an empty list yields an
 * empty list, and the caller's array is never mutated. Tier-2 names are
 * name-sorted among themselves so a run is reproducible regardless of the
 * order the registry happened to return.
 *
 * Note there is deliberately no "unknown package" signal. Landing in tier 2 is
 * the normal, correct outcome for everything that is not a dependency root —
 * flagging it would fire on every package on every run and carry nothing
 * actionable.
 */
export const orderPackagesForInstall = (
    names: readonly string[],
): readonly string[] => {
    // Deduplicated by NORMALIZED name, not just by exact string. Two spellings
    // of one package — `Veevart Data Model` and `VeevartDataModel` — are the
    // same package, and letting both through would submit two install jobs for
    // it in a single run. Exact-string matching could not produce that; adding
    // normalized root matching could, so the dedupe has to be normalized too.
    // Wherever a package is ordered, it is ordered ONCE.
    const seen = new Set<string>();
    const distinct: string[] = [];
    for (const name of names) {
        const key = normalizeName(name);
        if (seen.has(key)) continue;
        seen.add(key);
        distinct.push(name); // first spelling the registry gave us wins
    }

    // Match on the normalized name but emit the REGISTRY's spelling: the
    // caller looks the 04t up by that exact string, so returning our own
    // spelling of a root would break the lookup for the package we just
    // took the trouble to order correctly.
    const claimed = new Set<string>();
    const roots: string[] = [];
    for (const tier of KNOWN_TIERS) {
        for (const root of tier) {
            const wanted = normalizeName(root);
            const match = distinct.find(
                (actual) =>
                    !claimed.has(actual) && normalizeName(actual) === wanted,
            );
            if (match === undefined) continue;
            roots.push(match);
            claimed.add(match);
        }
    }

    const rest = distinct
        .filter((name) => !claimed.has(name))
        .sort((a, b) => a.localeCompare(b));

    return [...roots, ...rest];
};
