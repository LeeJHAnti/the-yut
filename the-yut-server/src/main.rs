mod admin;
mod bot;
mod game;
mod messages;
mod room;
mod ws_handler;

use actix_web::{web, App, HttpServer, middleware, HttpResponse};
use actix_web::http::header;
use actix_files as fs;
use std::collections::HashMap;
use std::sync::Arc;

use room::RoomMap;

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    env_logger::init_from_env(env_logger::Env::default().default_filter_or("info"));

    let host = std::env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port = std::env::var("PORT").unwrap_or_else(|_| "9001".to_string());
    let bind_addr = format!("{}:{}", host, port);

    let rooms: RoomMap = Arc::new(parking_lot::Mutex::new(HashMap::new()));

    log::info!("Starting The Yut server on {}", bind_addr);
    log::info!("WebSocket endpoint: ws://{}/ws", bind_addr);
    log::info!("Static files served from ./static/");

    HttpServer::new(move || {
        App::new()
            .wrap(middleware::Logger::default())
            .wrap(
                middleware::DefaultHeaders::new()
                    // Disable browser caching so exports are always fresh
                    .add((header::CACHE_CONTROL, "no-cache, no-store, must-revalidate"))
                    .add((header::PRAGMA, "no-cache"))
                    .add((header::EXPIRES, "0"))
                    // NOTE: COOP/COEP removed — threads are disabled (GODOT_THREADS_ENABLED=false)
                    // and require-corp blocks cross-origin AdSense scripts.
            )
            .app_data(web::Data::new(rooms.clone()))
            // WebSocket route MUST be registered before static files
            .route("/ws", web::get().to(ws_handler::ws_handler))
            // Admin REST API routes — registered before static files
            .route("/admin/stats", web::get().to(admin::get_server_stats))
            .route("/admin/rooms", web::get().to(admin::list_rooms))
            .route("/admin/rooms/{code}", web::get().to(admin::get_room_detail))
            .route("/admin/rooms/{code}", web::delete().to(admin::delete_room))
            .route("/admin/rooms/{code}/players/{player_id}", web::delete().to(admin::kick_player))
            // Static files served at root - this is a catch-all so it goes last
            .service(
                fs::Files::new("/", "./static")
                    .index_file("index.html")
                    .prefer_utf8(true),
            )
    })
    .bind(&bind_addr)?
    .workers(2)
    .run()
    .await
}
