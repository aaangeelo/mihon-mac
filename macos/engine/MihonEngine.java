/**
 * Native-app bootstrap for the unmodified Suwayomi 2.4.2366 server.
 * Its standard MainKt starts asynchronous GraphQL initialization before Koin
 * registers ServerConfig. On a fresh root this races static table initialization.
 * Initialize the application first; Javalin initializes GraphQL on demand.
 */
public final class MihonEngine {
    public static void main(String[] args) {
        suwayomi.tachidesk.server.ServerSetupKt.applicationSetup();
        suwayomi.tachidesk.server.JavalinSetup.INSTANCE.javalinSetup();
    }
}
