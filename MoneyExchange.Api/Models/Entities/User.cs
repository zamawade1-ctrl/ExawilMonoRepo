using System.ComponentModel.DataAnnotations;
using System.Text.Json.Serialization;

namespace MoneyExchange.Api.Models.Entities;

/// <summary>
/// A signed-in identity and its login credentials. Since the switch away from Google Sign-In the
/// primary path is username/email + password (<see cref="PasswordHash"/>); the old Google
/// subject id is kept nullable for the dormant Google path. Each User owns exactly one
/// <see cref="Customer"/> forwarding profile (1-to-1 via <see cref="Customer.UserId"/>), created
/// alongside the User at sign-up.
/// </summary>
public class User
{
    public int Id { get; set; }

    /// <summary>
    /// Optional now: since the switch to phone + OTP auth, email is no longer collected at
    /// sign-up. Kept nullable so the dormant Google path (which supplies an email) still works.
    /// </summary>
    [MaxLength(320)]
    public string? Email { get; set; }

    /// <summary>
    /// The primary login identity: the customer signs up / signs in with their phone number and a
    /// one-time OTP. Unique. Stored in E.164-ish normalized form by the repository.
    /// </summary>
    [MaxLength(20)]
    public string? PhoneNumber { get; set; }

    /// <summary>Login username. Unique (case-insensitive match in the repository). Legacy/optional.</summary>
    [MaxLength(60)]
    public string? Username { get; set; }

    /// <summary>
    /// PBKDF2 hash (ASP.NET Core <c>PasswordHasher</c> format) of the customer's 6-digit
    /// <b>app-lock PIN</b> — the custom PIN that unlocks the app on each open, replacing the old
    /// device-credential lock. Distinct from the account password and from the forwarding PINs.
    /// Null until the customer sets it (right after their first OTP verification). Reset via OTP if
    /// forgotten. <see cref="JsonIgnore"/>d so it never leaves the API.
    /// </summary>
    [MaxLength(400), JsonIgnore]
    public string? AppPinHash { get; set; }

    /// <summary>When the free trial started (normally the account-creation time).</summary>
    public DateTime TrialStartedAtUtc { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// True once this account's free trial has been "spent" and must never be re-granted. Set when
    /// an account is created on a device (<see cref="DeviceId"/>) that already has a prior record —
    /// including a soft-deleted one — so deleting and re-registering (even with a different phone
    /// number) can't mint a fresh trial. When true the plan calculation treats the trial as already
    /// ended regardless of <see cref="TrialStartedAtUtc"/> (see <c>PlanCalculator.TrialEndsAt</c>).
    /// </summary>
    public bool TrialConsumed { get; set; }

    /// <summary>
    /// When the customer's paid plan is valid through, or null if they've never paid. While this is
    /// in the future the customer is on the <b>Pro</b> plan; otherwise access depends on the trial
    /// window (see <see cref="TrialStartedAtUtc"/>). Set by the payment flow (Telesom, stubbed).
    /// </summary>
    public DateTime? PlanPaidUntilUtc { get; set; }

    /// <summary>
    /// When the current paid (Pro) period began — the anchor for the client's progress ring, so it
    /// can show how much of *this* grant is left. Set when a code is redeemed from an inactive plan
    /// (kept when merely extending an active one). Null if never paid.
    /// </summary>
    public DateTime? PlanStartedAtUtc { get; set; }

    /// <summary>
    /// The duration (in minutes) the most recently redeemed activation code granted — the source for
    /// the admin's "plan kind" label (1 month / 6 months / 1 year / Forever). A very large value
    /// (see <c>PlanKinds.ForeverMinutes</c>) encodes a never-expiring "Forever" plan. Null until the
    /// user has redeemed a paid plan.
    /// </summary>
    public int? PlanDurationMinutes { get; set; }

    /// <summary>
    /// USD price of the plan the user most recently redeemed (copied from the redeemed code's
    /// <see cref="ActivationCode.PriceUsd"/>), so the admin billing view shows the exact amount even
    /// when two plans share a duration (the $10 vs $5 one-month plans). Null = unpriced/legacy (admin
    /// billing falls back to the duration-derived price); 0 = an explicit free plan.
    /// </summary>
    public int? PlanPriceUsd { get; set; }

    /// <summary>
    /// When this account was last mutated by an admin action (device/password reset, plan change,
    /// phone edit) or a plan redemption. Drives the admin list's "most-recently-edited first"
    /// ordering. Null for accounts untouched since before this field existed (falls back to
    /// <see cref="CreatedAt"/> for ordering).
    /// </summary>
    public DateTime? LastModifiedAtUtc { get; set; }

    /// <summary>
    /// PBKDF2 hash of the password (ASP.NET Core <c>PasswordHasher</c> format), never the raw
    /// password. Null only for legacy Google-only identities. <see cref="JsonIgnore"/>d so it's
    /// never serialized out through the API.
    /// </summary>
    [MaxLength(400), JsonIgnore]
    public string? PasswordHash { get; set; }

    /// <summary>The "sub" claim from Google's ID token. Null for password accounts (legacy/dormant Google path).</summary>
    [MaxLength(255)]
    public string? GoogleSubjectId { get; set; }

    /// <summary>Access level: a regular customer (<see cref="UserRole.User"/>) or an <see cref="UserRole.Admin"/>.</summary>
    public UserRole Role { get; set; } = UserRole.User;

    /// <summary>
    /// Whether the 6-digit app-lock PIN is required. Default true (the app forces setting one on
    /// first run); a user can turn it off from settings, which clears <see cref="AppPinHash"/> and
    /// drops the lock gate so the app opens straight in.
    /// </summary>
    public bool PinEnabled { get; set; } = true;

    [Required, MaxLength(120)]
    public string FullName { get; set; } = string.Empty;

    [MaxLength(500)]
    public string? ProfilePictureUrl { get; set; }

    /// <summary>The forwarding profile owned by this identity (1-to-1). Created at sign-up.</summary>
    public Customer? Customer { get; set; }

    /// <summary>
    /// The device this account is bound to: a hash of the phone's stable hardware id
    /// (Android <c>ANDROID_ID</c>), set the first time the account signs up / signs in. Login from a
    /// device whose id doesn't match is rejected, so shared credentials can't be used on a second
    /// phone. Null until first bound, or after an admin reset (which re-opens binding on next login).
    /// </summary>
    [MaxLength(128)]
    public string? DeviceId { get; set; }

    /// <summary>A human-readable label for the bound device (e.g. "Samsung SM-A065F"), for support.</summary>
    [MaxLength(120)]
    public string? DeviceLabel { get; set; }

    /// <summary>When the current <see cref="DeviceId"/> was bound.</summary>
    public DateTime? DeviceRegisteredAtUtc { get; set; }

    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

    public DateTime LastLoginAtUtc { get; set; } = DateTime.UtcNow;

    /// <summary>
    /// Soft-delete marker. Account deletion no longer removes the row: instead it sets this true and
    /// nulls the reusable identity fields (<see cref="PhoneNumber"/>, <see cref="Username"/>,
    /// <see cref="Email"/>, <see cref="PasswordHash"/>, <see cref="AppPinHash"/>,
    /// <see cref="GoogleSubjectId"/>) so they can be registered again, while keeping the
    /// device-binding fields (<see cref="DeviceId"/>, <see cref="DeviceLabel"/>) so the device's
    /// trial-used history survives. A global query filter hides <c>IsDeleted</c> rows from every
    /// normal query (login, admin lists, subscription) — the only reader that opts back in
    /// (via <c>IgnoreQueryFilters</c>) is registration's device-history lookup.
    /// </summary>
    public bool IsDeleted { get; set; }

    /// <summary>When the account was soft-deleted (see <see cref="IsDeleted"/>); null if active.</summary>
    public DateTime? DeletedAtUtc { get; set; }
}
