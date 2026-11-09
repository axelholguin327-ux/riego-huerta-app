-- =============================================================
--  Huerta Manzanos · Modelo de datos (MySQL 8)
--  Sistema IoT de riego para huertas de manzana
--  Corresponde al diagrama docs/diagrama_ER.png
-- =============================================================
CREATE DATABASE IF NOT EXISTS huerta_manzanos
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE huerta_manzanos;

-- Usuarios de la app (dueño/administrador y encargados de riego)
CREATE TABLE usuario (
  id_usuario     INT AUTO_INCREMENT PRIMARY KEY,
  nombre         VARCHAR(100) NOT NULL,
  email          VARCHAR(120) NOT NULL UNIQUE,
  password_hash  VARCHAR(255) NOT NULL,            -- bcrypt
  rol            ENUM('admin','encargado') NOT NULL DEFAULT 'encargado',
  activo         BOOLEAN NOT NULL DEFAULT TRUE,
  creado_en      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE huerta (
  id_huerta      INT AUTO_INCREMENT PRIMARY KEY,
  id_propietario INT NOT NULL,
  nombre         VARCHAR(100) NOT NULL,
  ubicacion      VARCHAR(150),
  superficie_m2  DECIMAL(10,2),
  FOREIGN KEY (id_propietario) REFERENCES usuario(id_usuario)
);

-- Nodo ESP32 registrado en ThingsBoard
CREATE TABLE dispositivo (
  id_dispositivo  INT AUTO_INCREMENT PRIMARY KEY,
  id_huerta       INT NOT NULL,
  nombre          VARCHAR(60) NOT NULL,             -- nodo-huerta-01
  tb_device_id    VARCHAR(64) NOT NULL UNIQUE,      -- id del dispositivo en ThingsBoard
  firmware        VARCHAR(20),
  modo            ENUM('auto','manual') NOT NULL DEFAULT 'auto',
  estado          ENUM('activo','inactivo') NOT NULL DEFAULT 'activo',
  ultimo_contacto DATETIME,
  FOREIGN KEY (id_huerta) REFERENCES huerta(id_huerta) ON DELETE CASCADE
);

-- Zona de riego (una electroválvula + un sensor YL-69)
CREATE TABLE zona (
  id_zona            INT AUTO_INCREMENT PRIMARY KEY,
  id_dispositivo     INT NOT NULL,
  numero             TINYINT NOT NULL,              -- 1 o 2
  nombre             VARCHAR(60) NOT NULL,
  umbral_humedad_pct TINYINT NOT NULL DEFAULT 50 CHECK (umbral_humedad_pct BETWEEN 0 AND 100),
  valvula_abierta    BOOLEAN NOT NULL DEFAULT FALSE,
  UNIQUE (id_dispositivo, numero),
  FOREIGN KEY (id_dispositivo) REFERENCES dispositivo(id_dispositivo) ON DELETE CASCADE
);

-- Lectura periódica del nodo (cada 10 s) con datos ambientales
CREATE TABLE lectura (
  id_lectura     BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_dispositivo INT NOT NULL,
  fecha_hora     DATETIME NOT NULL,
  temp_c         DECIMAL(4,1),
  hum_amb        DECIMAL(4,1),
  INDEX idx_lectura_fecha (id_dispositivo, fecha_hora),
  FOREIGN KEY (id_dispositivo) REFERENCES dispositivo(id_dispositivo) ON DELETE CASCADE
);

-- Humedad de suelo de cada zona dentro de una lectura (1:N)
CREATE TABLE lectura_suelo (
  id_lectura  BIGINT NOT NULL,
  id_zona     INT NOT NULL,
  humedad_pct TINYINT NOT NULL CHECK (humedad_pct BETWEEN 0 AND 100),
  PRIMARY KEY (id_lectura, id_zona),
  FOREIGN KEY (id_lectura) REFERENCES lectura(id_lectura) ON DELETE CASCADE,
  FOREIGN KEY (id_zona) REFERENCES zona(id_zona) ON DELETE CASCADE
);

CREATE TABLE tarjeta_rfid (
  id_tarjeta  INT AUTO_INCREMENT PRIMARY KEY,
  id_usuario  INT NOT NULL,
  uid         VARCHAR(20) NOT NULL UNIQUE,          -- UID leído por el RC522
  activa      BOOLEAN NOT NULL DEFAULT TRUE,
  fecha_alta  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE CASCADE
);

-- Zonas que puede regar cada tarjeta (relación N:M)
CREATE TABLE tarjeta_zona (
  id_tarjeta INT NOT NULL,
  id_zona    INT NOT NULL,
  PRIMARY KEY (id_tarjeta, id_zona),
  FOREIGN KEY (id_tarjeta) REFERENCES tarjeta_rfid(id_tarjeta) ON DELETE CASCADE,
  FOREIGN KEY (id_zona) REFERENCES zona(id_zona) ON DELETE CASCADE
);

-- Cada lectura de tarjeta en el nodo, autorizada o denegada
CREATE TABLE acceso_rfid (
  id_acceso      BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_dispositivo INT NOT NULL,
  id_tarjeta     INT NULL,                          -- NULL si el UID no está registrado
  uid_leido      VARCHAR(20) NOT NULL,
  autorizado     BOOLEAN NOT NULL,
  accion         ENUM('manual_irrigation','denied') NOT NULL,
  fecha_hora     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (id_dispositivo) REFERENCES dispositivo(id_dispositivo) ON DELETE CASCADE,
  FOREIGN KEY (id_tarjeta) REFERENCES tarjeta_rfid(id_tarjeta) ON DELETE SET NULL
);

-- Cada activación de riego: quién, cómo, cuánto y con qué resultado
CREATE TABLE evento_riego (
  id_evento       BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_zona         INT NOT NULL,
  id_usuario      INT NULL,                         -- NULL en riego automático
  id_acceso       BIGINT NULL UNIQUE,               -- 0..1 acceso RFID que lo originó
  origen          ENUM('auto','app','rfid','dashboard') NOT NULL,
  inicio          DATETIME NOT NULL,
  fin             DATETIME NULL,
  duracion_s      SMALLINT CHECK (duracion_s BETWEEN 1 AND 600),
  humedad_inicial TINYINT,
  humedad_final   TINYINT,
  INDEX idx_evento_zona (id_zona, inicio),
  FOREIGN KEY (id_zona) REFERENCES zona(id_zona) ON DELETE CASCADE,
  FOREIGN KEY (id_usuario) REFERENCES usuario(id_usuario) ON DELETE SET NULL,
  FOREIGN KEY (id_acceso) REFERENCES acceso_rfid(id_acceso) ON DELETE SET NULL
);

-- Alarmas creadas por el Rule Engine de ThingsBoard
CREATE TABLE alarma (
  id_alarma      BIGINT AUTO_INCREMENT PRIMARY KEY,
  id_dispositivo INT NOT NULL,
  id_zona        INT NULL,
  tipo           VARCHAR(60) NOT NULL,              -- 'Humedad de suelo baja'
  severidad      ENUM('minor','major','critical') NOT NULL,
  estado         ENUM('activa','reconocida','resuelta') NOT NULL DEFAULT 'activa',
  valor          DECIMAL(6,2),
  creada_en      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  reconocida_por INT NULL,
  resuelta_en    DATETIME NULL,
  INDEX idx_alarma_estado (estado, creada_en),
  FOREIGN KEY (id_dispositivo) REFERENCES dispositivo(id_dispositivo) ON DELETE CASCADE,
  FOREIGN KEY (id_zona) REFERENCES zona(id_zona) ON DELETE SET NULL,
  FOREIGN KEY (reconocida_por) REFERENCES usuario(id_usuario) ON DELETE SET NULL
);

-- ---------------- Datos de ejemplo ----------------
INSERT INTO usuario (nombre, email, password_hash, rol) VALUES
  ('Axel Holguín',  'axel@huerta.mx',   '$2b$10$hash_de_ejemplo', 'admin'),
  ('Daniel Varela', 'daniel@huerta.mx', '$2b$10$hash_de_ejemplo', 'encargado'),
  ('Reyes Zubía',   'reyes@huerta.mx',  '$2b$10$hash_de_ejemplo', 'encargado');
INSERT INTO huerta (id_propietario, nombre, ubicacion, superficie_m2)
  VALUES (1, 'Huerta Manzanos', 'Cd. Cuauhtémoc, Chihuahua', 1200);
INSERT INTO dispositivo (id_huerta, nombre, tb_device_id, firmware)
  VALUES (1, 'nodo-huerta-01', 'tb-device-uuid-ejemplo', '1.2.0');
INSERT INTO zona (id_dispositivo, numero, nombre) VALUES (1, 1, 'Zona 1'), (1, 2, 'Zona 2');
INSERT INTO tarjeta_rfid (id_usuario, uid) VALUES (1, 'SIM00001'), (2, 'SIM00002');
INSERT INTO tarjeta_zona VALUES (1, 1), (1, 2), (2, 2);
