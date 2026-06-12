function search_list() {
    return [
        "google_sem",
        "bing_ads",
        "search_direct"
    ];
}

function facebook_list() {
    return [
        "fb_ads",
        "facebook_feed"
    ];
}

function email_list() {
    return [
        "newsletter_v1",
        "email_blast",
        "promo_code"
    ];
}

function display_list() {
    return [
        "gdn_banner",
        "display_ad_net"
    ];
}

function organic_list() {
    return [
        "unknown_blog",
        "ghost_traffic"
    ];
}


function format_list(list) {
    return list.map(src => `"${src}"`).join(", ");
}

function map_source(col) {
    return `
    CASE
        WHEN LOWER(${col}) IN (${format_list(search_list())}) THEN "Search"
        WHEN LOWER(${col}) IN (${format_list(facebook_list())}) THEN "Facebook"
        WHEN LOWER(${col}) IN (${format_list(email_list())}) THEN "Email"
        WHEN LOWER(${col}) IN (${format_list(display_list())}) THEN "Display"
        WHEN LOWER(${col}) IN (${format_list(organic_list())}) THEN "Organic"
        ELSE NULL
    END`;
}

function deduplicate(id_col, order_col) {
    return `QUALIFY ROW_NUMBER() OVER(PARTITION BY ${id_col} ORDER BY ${order_col} DESC) = 1`;
}

function normalize_date(col) {
    return `
    COALESCE(
        SAFE.PARSE_DATE("%Y-%m-%d", ${col}),
        SAFE.PARSE_DATE("%m/%d/%y", ${col}),
        SAFE.PARSE_DATE("%m/%d/%Y", ${col})
      )`;
}

function known_sources() {
    return [
        ...search_list(),
        ...facebook_list(),
        ...email_list(),
        ...display_list(),
        ...organic_list()
    ];
}

function is_known_source(col) {
    return `LOWER(${col}) IN (${format_list(known_sources())})`;
}


module.exports = { map_source, deduplicate, normalize_date, known_sources, is_known_source };