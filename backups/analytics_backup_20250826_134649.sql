-- MySQL dump 10.13  Distrib 9.4.0, for macos15.4 (arm64)
--
-- Host: localhost    Database: breakout_analytics
-- ------------------------------------------------------
-- Server version	8.0.43

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!50503 SET NAMES utf8mb4 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `daily_statistics`
--

DROP TABLE IF EXISTS `daily_statistics`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `daily_statistics` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `strategy_name` varchar(100) NOT NULL,
  `strategy_version` varchar(20) NOT NULL,
  `symbol` varchar(20) NOT NULL,
  `timeframe` varchar(10) NOT NULL,
  `date` date NOT NULL,
  `total_trades` int NOT NULL DEFAULT '0',
  `winning_trades` int NOT NULL DEFAULT '0',
  `losing_trades` int NOT NULL DEFAULT '0',
  `net_profit` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `win_rate` decimal(5,2) NOT NULL DEFAULT '0.00',
  `average_profit_per_trade` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `max_drawdown` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_daily_stats` (`strategy_name`,`strategy_version`,`symbol`,`timeframe`,`date`),
  KEY `idx_strategy_date` (`strategy_name`,`strategy_version`,`symbol`,`timeframe`,`date`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `daily_statistics`
--

LOCK TABLES `daily_statistics` WRITE;
/*!40000 ALTER TABLE `daily_statistics` DISABLE KEYS */;
/*!40000 ALTER TABLE `daily_statistics` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `market_conditions`
--

DROP TABLE IF EXISTS `market_conditions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `market_conditions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `trade_id` bigint NOT NULL,
  `symbol` varchar(20) NOT NULL,
  `timeframe` varchar(10) NOT NULL,
  `rsi` decimal(8,4) DEFAULT NULL,
  `stoch_main` decimal(8,4) DEFAULT NULL,
  `stoch_signal` decimal(8,4) DEFAULT NULL,
  `macd_main` decimal(8,4) DEFAULT NULL,
  `macd_signal` decimal(8,4) DEFAULT NULL,
  `bb_upper` decimal(20,8) DEFAULT NULL,
  `bb_lower` decimal(20,8) DEFAULT NULL,
  `cci` decimal(10,4) DEFAULT NULL COMMENT 'Commodity Channel Index - expanded range for extreme values',
  `momentum` decimal(12,4) DEFAULT NULL,
  `volume_ratio` decimal(10,4) DEFAULT NULL,
  `price_change` decimal(10,6) DEFAULT NULL,
  `volatility` decimal(10,6) DEFAULT NULL,
  `spread` decimal(20,8) DEFAULT NULL,
  `session_hour` int DEFAULT NULL,
  `day_of_week` int DEFAULT NULL,
  `month` int DEFAULT NULL,
  `recorded_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `williams_r` decimal(8,4) DEFAULT NULL COMMENT 'Williams %R indicator value',
  `force_index` decimal(15,4) DEFAULT NULL COMMENT 'Force Index indicator value',
  PRIMARY KEY (`id`),
  KEY `idx_trade_id` (`trade_id`),
  KEY `idx_symbol_timeframe` (`symbol`,`timeframe`),
  KEY `idx_recorded_at` (`recorded_at`),
  CONSTRAINT `market_conditions_ibfk_1` FOREIGN KEY (`trade_id`) REFERENCES `trades` (`trade_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Removed ATR column - not used by ML models';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `market_conditions`
--

LOCK TABLES `market_conditions` WRITE;
/*!40000 ALTER TABLE `market_conditions` DISABLE KEYS */;
INSERT INTO `market_conditions` VALUES (1,0,'EURUSD+','PERIOD_M15',64.1400,85.3700,74.8000,0.0000,0.0000,1.16284000,1.16284000,90.8200,100.2200,0.4800,0.000000,0.000000,0.00000000,14,2,8,'2025-08-26 11:42:06',-3.4600,-0.0100),(2,0,'EURUSD+','PERIOD_M15',61.3400,79.1300,72.7200,0.0000,0.0000,1.16284000,1.16284000,84.4700,100.2000,0.8300,-0.000200,0.000200,0.00000000,14,2,8,'2025-08-26 11:42:06',-8.7800,-0.1400),(3,0,'EURUSD+','PERIOD_M15',62.0000,73.0600,71.1600,0.0000,0.0000,1.16293000,1.16293000,75.9300,100.2300,0.1300,0.000500,0.000500,0.00000000,14,2,8,'2025-08-26 11:42:06',-2.7700,0.0600),(4,0,'EURUSD+','PERIOD_M15',65.6700,79.0800,73.1700,0.0000,0.0000,1.16293000,1.16293000,99.9300,100.2900,0.5000,0.001000,0.001000,0.00000000,14,2,8,'2025-08-26 11:42:06',-0.2100,0.4700),(5,373794253,'EURUSD+','PERIOD_M15',66.9000,80.2300,73.5600,0.0000,0.0000,1.16293000,1.16293000,109.1100,100.3100,0.5400,0.001300,0.001300,0.00001000,14,2,8,'2025-08-26 11:42:06',-0.2000,0.6100),(6,0,'ETHUSD','PERIOD_H1',41.5400,53.9900,54.6200,-49.1600,-66.0600,4449.69000000,4449.69000000,82.3300,101.6900,0.5700,-0.003900,0.003900,2.98000000,14,2,8,'2025-08-26 11:42:09',-27.2000,-67621.6600),(7,0,'ETHUSD','PERIOD_H1',41.2600,52.6500,54.1800,-49.3700,-66.0800,4449.69000000,4449.69000000,78.2500,101.6300,0.6900,-0.004500,0.004500,3.00000000,14,2,8,'2025-08-26 11:42:09',-28.8500,-93689.2000),(8,0,'ETHUSD','PERIOD_H1',40.2000,47.4900,52.4600,-50.1600,-66.1700,4449.69000000,4449.69000000,63.0800,101.4000,0.7900,-0.006700,0.006700,2.97000000,14,2,8,'2025-08-26 11:42:09',-35.2400,-161778.8700),(9,0,'ETHUSD','PERIOD_H1',40.6100,49.5100,53.1300,-49.8500,-66.1400,4449.69000000,4449.69000000,63.7900,101.4900,0.9300,-0.005800,0.005800,3.02000000,14,2,8,'2025-08-26 11:42:09',-32.7500,-165575.0200),(10,373794393,'ETHUSD','PERIOD_H1',40.7600,50.2400,53.3700,-49.7400,-66.1300,4449.69000000,4449.69000000,65.0300,101.5200,0.9400,-0.005500,0.005500,2.97000000,14,2,8,'2025-08-26 11:42:09',-31.8400,-158037.6000),(11,0,'GBPUSD+','PERIOD_H1',55.6100,95.7900,89.8700,0.0000,0.0000,1.34670000,1.34670000,134.3700,100.2300,0.2900,0.000400,0.000400,0.00000000,14,2,8,'2025-08-26 11:43:33',-10.5700,0.6600),(12,0,'GBPUSD+','PERIOD_H1',54.2300,93.4400,89.0800,0.0000,0.0000,1.34670000,1.34670000,127.8300,100.2100,0.3600,0.000200,0.000200,0.00000000,14,2,8,'2025-08-26 11:43:33',-16.6700,0.3400),(13,0,'GBPUSD+','PERIOD_H1',56.0000,96.4800,90.1000,0.0000,0.0000,1.34670000,1.34670000,136.2600,100.2400,0.4400,0.000500,0.000500,0.00000000,14,2,8,'2025-08-26 11:43:33',-8.7800,1.1600),(14,0,'GBPUSD+','PERIOD_H1',56.9900,95.0600,89.6200,0.0000,0.0000,1.34670000,1.34670000,150.1300,100.2600,0.5400,0.000700,0.000700,0.00001000,14,2,8,'2025-08-26 11:43:33',-4.2900,1.9800),(15,373795804,'GBPUSD+','PERIOD_H1',57.0200,95.1200,89.6500,0.0000,0.0000,1.34670000,1.34670000,150.3100,100.2600,0.5400,0.000700,0.000700,0.00000000,14,2,8,'2025-08-26 11:43:33',-4.1100,2.0100),(16,0,'ETHUSD','PERIOD_M30',49.7400,55.0900,52.5100,-8.3800,-15.6300,4411.49000000,4411.49000000,142.1700,100.2000,0.8500,-0.001600,0.001600,2.96000000,14,2,8,'2025-08-26 11:43:36',-44.1200,-22313.2500),(17,0,'ETHUSD','PERIOD_M30',46.4500,44.6900,49.0400,-9.5800,-15.7600,4411.49000000,4411.49000000,80.8900,99.8600,1.1100,-0.005000,0.005000,3.04000000,14,2,8,'2025-08-26 11:43:36',-64.9600,-90976.4300),(18,0,'ETHUSD','PERIOD_M30',46.5900,45.1800,49.2000,-9.5300,-15.7600,4411.49000000,4411.49000000,73.2500,99.8800,1.3300,-0.004800,0.004800,2.97000000,14,2,8,'2025-08-26 11:43:36',-63.9900,-105349.8800),(19,0,'ETHUSD','PERIOD_M30',44.8000,32.4500,43.3000,-9.6700,-14.2100,4416.97000000,4416.97000000,-107.5300,99.4800,0.1100,-0.002200,0.002200,3.02000000,14,2,8,'2025-08-26 11:43:36',-75.5500,-5447.3100),(20,0,'ETHUSD','PERIOD_M30',44.8400,32.7300,43.3900,-9.6600,-14.2100,4416.97000000,4416.97000000,-110.2900,99.4900,0.3000,-0.002200,0.002200,3.00000000,14,2,8,'2025-08-26 11:43:36',-75.2900,-14775.0400),(21,0,'XAUUSD+','PERIOD_M5',65.1400,95.2300,93.1600,0.7400,-0.5600,3372.02000000,3372.02000000,120.6100,100.1700,0.1100,0.000200,0.000200,0.08000000,14,2,8,'2025-08-26 11:46:16',-0.2800,63.8000),(22,0,'XAUUSD+','PERIOD_M5',65.9400,96.7100,94.4700,1.0000,-0.2600,3372.27000000,3372.27000000,105.4500,100.2000,0.2100,0.000000,0.000000,0.10000000,14,2,8,'2025-08-26 11:46:16',-1.2400,-1.7100),(23,0,'XAUUSD+','PERIOD_M5',57.7300,66.4700,83.5200,1.0100,0.0200,3372.67000000,3372.67000000,66.3800,100.1700,0.3200,-0.000500,0.000500,0.10000000,14,2,8,'2025-08-26 11:46:16',-24.7000,-462.0000),(24,373792837,'XAUUSD+','PERIOD_M5',60.3600,71.1200,85.0700,1.0600,0.0300,3372.67000000,3372.67000000,69.9300,100.1900,0.3700,-0.000300,0.000300,0.09000000,14,2,8,'2025-08-26 11:46:16',-19.5100,-318.6000),(25,0,'XAUUSD+','PERIOD_M5',67.4100,73.3500,81.2100,1.3600,0.3400,3373.06000000,3373.06000000,91.2700,100.3200,0.2000,0.000200,0.000200,0.10000000,14,2,8,'2025-08-26 11:46:16',-3.2300,161.8200);
/*!40000 ALTER TABLE `market_conditions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `migration_log`
--

DROP TABLE IF EXISTS `migration_log`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `migration_log` (
  `id` int NOT NULL AUTO_INCREMENT,
  `filename` varchar(255) NOT NULL,
  `executed_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `status` enum('SUCCESS','FAILED') DEFAULT 'SUCCESS',
  `error_message` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_migration` (`filename`),
  KEY `idx_executed_at` (`executed_at`)
) ENGINE=InnoDB AUTO_INCREMENT=17 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Tracks which database migrations have been executed';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `migration_log`
--

LOCK TABLES `migration_log` WRITE;
/*!40000 ALTER TABLE `migration_log` DISABLE KEYS */;
INSERT INTO `migration_log` VALUES (1,'000_create_migration_log.sql','2025-08-26 11:41:02','SUCCESS',NULL),(2,'001_create_initial_tables.sql','2025-08-26 11:41:02','SUCCESS',NULL),(3,'002_add_test_values.sql','2025-08-26 11:41:02','SUCCESS',NULL),(4,'003_add_ml_trade_logging.sql','2025-08-26 11:41:03','SUCCESS',NULL),(5,'004_use_mt5_ticket_as_trade_id.sql','2025-08-26 11:41:03','SUCCESS',NULL),(6,'005_fix_momentum_column_size.sql','2025-08-26 11:41:03','SUCCESS',NULL),(7,'006_remove_breakout_columns.sql','2025-08-26 11:41:03','SUCCESS',NULL),(8,'007_remove_adx_column.sql','2025-08-26 11:41:03','SUCCESS',NULL),(9,'008_add_missing_columns_to_ml_predictions.sql','2025-08-26 11:41:04','SUCCESS',NULL),(10,'009_expand_cci_column_range.sql','2025-08-26 11:41:04','SUCCESS',NULL),(11,'010_add_missing_indicator_columns.sql','2025-08-26 11:41:04','SUCCESS',NULL),(12,'011_remove_atr_column.sql','2025-08-26 11:41:04','SUCCESS',NULL),(13,'012_fix_ml_trade_logs_price_columns.sql','2025-08-26 11:41:04','SUCCESS',NULL),(14,'013_fix_missing_trade_data.sql','2025-08-26 11:41:04','SUCCESS',NULL),(15,'014_fix_missing_duration_seconds.sql','2025-08-26 11:41:04','SUCCESS',NULL),(16,'015_fix_orphaned_ml_trade_logs.sql','2025-08-26 11:41:04','SUCCESS',NULL);
/*!40000 ALTER TABLE `migration_log` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ml_model_performance`
--

DROP TABLE IF EXISTS `ml_model_performance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ml_model_performance` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `model_name` varchar(100) NOT NULL,
  `model_type` enum('BUY','SELL','COMBINED') NOT NULL,
  `symbol` varchar(20) NOT NULL,
  `timeframe` varchar(10) NOT NULL,
  `period_start` datetime NOT NULL,
  `period_end` datetime NOT NULL,
  `total_predictions` int NOT NULL DEFAULT '0',
  `correct_predictions` int NOT NULL DEFAULT '0',
  `accuracy` decimal(5,4) NOT NULL DEFAULT '0.0000',
  `average_confidence` decimal(5,4) NOT NULL DEFAULT '0.0000',
  `average_prediction_probability` decimal(5,4) NOT NULL DEFAULT '0.0000',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_model_period` (`model_name`,`model_type`,`symbol`,`timeframe`,`period_start`,`period_end`),
  KEY `idx_model_symbol` (`model_name`,`model_type`,`symbol`,`timeframe`),
  KEY `idx_period` (`period_start`,`period_end`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ml_model_performance`
--

LOCK TABLES `ml_model_performance` WRITE;
/*!40000 ALTER TABLE `ml_model_performance` DISABLE KEYS */;
/*!40000 ALTER TABLE `ml_model_performance` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ml_predictions`
--

DROP TABLE IF EXISTS `ml_predictions`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ml_predictions` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `trade_id` bigint NOT NULL,
  `model_name` varchar(100) NOT NULL,
  `model_type` enum('BUY','SELL','COMBINED','TEST') NOT NULL,
  `prediction_probability` decimal(5,4) NOT NULL,
  `confidence_score` decimal(5,4) NOT NULL,
  `features_json` json DEFAULT NULL,
  `prediction_time` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `symbol` varchar(20) DEFAULT NULL COMMENT 'Symbol from EA data',
  `timeframe` varchar(10) DEFAULT NULL COMMENT 'Timeframe from EA data',
  `strategy_name` varchar(100) DEFAULT NULL COMMENT 'Strategy name from EA data',
  `strategy_version` varchar(20) DEFAULT NULL COMMENT 'Strategy version from EA data',
  PRIMARY KEY (`id`),
  KEY `idx_trade_id` (`trade_id`),
  KEY `idx_model` (`model_name`,`model_type`),
  KEY `idx_prediction_time` (`prediction_time`),
  CONSTRAINT `ml_predictions_ibfk_1` FOREIGN KEY (`trade_id`) REFERENCES `trades` (`trade_id`) ON DELETE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=26 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Added missing columns (symbol, timeframe, strategy_name, strategy_version) from EA data';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ml_predictions`
--

LOCK TABLES `ml_predictions` WRITE;
/*!40000 ALTER TABLE `ml_predictions` DISABLE KEYS */;
INSERT INTO `ml_predictions` VALUES (1,0,'buy_model_test','BUY',0.1940,0.6110,'{\"cci\": 90.8247493, \"rsi\": 64.14265973, \"month\": 8, \"spread\": 0.0, \"symbol\": \"EURUSD+\", \"bb_lower\": 1.162841, \"bb_upper\": 1.162841, \"momentum\": 100.22199659, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": 0.00045789, \"timeframe\": \"M15\", \"timestamp\": 1756218088, \"stoch_main\": 85.36585366, \"volatility\": 0.00001717, \"williams_r\": -3.46420323, \"day_of_week\": 2, \"force_index\": -0.00668, \"macd_signal\": 0.00017741, \"is_news_time\": false, \"price_change\": -0.00001717, \"session_hour\": 14, \"stoch_signal\": 74.79729302, \"volume_ratio\": 0.47851003}','2025-08-26 11:42:06','EURUSD+','M15','ML_Testing_EA_Testing','1.00'),(2,0,'sell_model_test','SELL',0.5850,0.1700,'{\"cci\": 90.8247493, \"rsi\": 64.14265973, \"month\": 8, \"spread\": 0.0, \"symbol\": \"EURUSD+\", \"bb_lower\": 1.162841, \"bb_upper\": 1.162841, \"momentum\": 100.22199659, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": 0.00045789, \"timeframe\": \"M15\", \"timestamp\": 1756218088, \"stoch_main\": 85.36585366, \"volatility\": 0.00001717, \"williams_r\": -3.46420323, \"day_of_week\": 2, \"force_index\": -0.00668, \"macd_signal\": 0.00017741, \"is_news_time\": false, \"price_change\": -0.00001717, \"session_hour\": 14, \"stoch_signal\": 74.79729302, \"volume_ratio\": 0.47851003}','2025-08-26 11:42:06','EURUSD+','M15','ML_Testing_EA_Testing','1.00'),(3,0,'sell_model_improved','SELL',0.0000,0.0000,'{\"cci\": 109.11423706, \"rsi\": 66.90094133, \"month\": 8, \"spread\": 0.00001, \"symbol\": \"EURUSD+\", \"bb_lower\": 1.1629295, \"bb_upper\": 1.1629295, \"momentum\": 100.30807094, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": 0.00052799, \"timeframe\": \"M15\", \"timestamp\": 1756219053, \"stoch_main\": 80.22988506, \"volatility\": 0.00125409, \"williams_r\": -0.19685039, \"day_of_week\": 2, \"force_index\": 0.60882, \"macd_signal\": 0.00025309, \"is_news_time\": false, \"price_change\": 0.00125409, \"session_hour\": 14, \"stoch_signal\": 73.55581739, \"volume_ratio\": 0.54296875}','2025-08-26 11:42:06','EURUSD+','M15','ML_Testing_EA_Testing','1.00'),(4,0,'buy_model_test','BUY',0.0910,0.8170,'{\"cci\": 105.88331694, \"rsi\": 65.7722467, \"month\": 8, \"spread\": 0.0, \"symbol\": \"EURUSD+\", \"bb_lower\": 1.1629295, \"bb_upper\": 1.1629295, \"momentum\": 100.28913921, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": 0.00051044, \"timeframe\": \"M15\", \"timestamp\": 1756219326, \"stoch_main\": 74.31818182, \"volatility\": 0.00106512, \"williams_r\": -5.45808967, \"day_of_week\": 2, \"force_index\": 0.95728, \"macd_signal\": 0.00025114, \"is_news_time\": false, \"price_change\": 0.00106512, \"session_hour\": 14, \"stoch_signal\": 71.58524964, \"volume_ratio\": 1.00520833}','2025-08-26 11:42:06','EURUSD+','M15','ML_Testing_EA_Testing','1.00'),(5,0,'sell_model_test','SELL',0.5900,0.1790,'{\"cci\": 105.88331694, \"rsi\": 65.7722467, \"month\": 8, \"spread\": 0.0, \"symbol\": \"EURUSD+\", \"bb_lower\": 1.1629295, \"bb_upper\": 1.1629295, \"momentum\": 100.28913921, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": 0.00051044, \"timeframe\": \"M15\", \"timestamp\": 1756219326, \"stoch_main\": 74.31818182, \"volatility\": 0.00106512, \"williams_r\": -5.45808967, \"day_of_week\": 2, \"force_index\": 0.95728, \"macd_signal\": 0.00025114, \"is_news_time\": false, \"price_change\": 0.00106512, \"session_hour\": 14, \"stoch_signal\": 71.58524964, \"volume_ratio\": 1.00520833}','2025-08-26 11:42:06','EURUSD+','M15','ML_Testing_EA_Testing','1.00'),(6,0,'sell_model_test','SELL',0.6240,0.2480,'{\"cci\": 82.32510119, \"rsi\": 41.54186539, \"month\": 8, \"spread\": 2.98, \"symbol\": \"ETHUSD\", \"bb_lower\": 4449.6935, \"bb_upper\": 4449.6935, \"momentum\": 101.69048802, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -49.16019535, \"timeframe\": \"H1\", \"timestamp\": 1756218113, \"stoch_main\": 53.98948629, \"volatility\": 0.00390325, \"williams_r\": -27.19773137, \"day_of_week\": 2, \"force_index\": -67621.66, \"macd_signal\": -66.06209506, \"is_news_time\": false, \"price_change\": -0.00390325, \"session_hour\": 14, \"stoch_signal\": 54.62189166, \"volume_ratio\": 0.56913652}','2025-08-26 11:42:09','ETHUSD','H1','ML_Testing_EA_Testing','1.00'),(7,0,'buy_model_test','BUY',0.3760,0.2480,'{\"cci\": 63.08404147, \"rsi\": 40.20266382, \"month\": 8, \"spread\": 2.97, \"symbol\": \"ETHUSD\", \"bb_lower\": 4449.6935, \"bb_upper\": 4449.6935, \"momentum\": 101.40352813, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": -50.1557509, \"timeframe\": \"H1\", \"timestamp\": 1756218715, \"stoch_main\": 47.49388435, \"volatility\": 0.00671413, \"williams_r\": -35.24104151, \"day_of_week\": 2, \"force_index\": -161778.87, \"macd_signal\": -66.17271234, \"is_news_time\": false, \"price_change\": -0.00671413, \"session_hour\": 14, \"stoch_signal\": 52.45669101, \"volume_ratio\": 0.79156943}','2025-08-26 11:42:09','ETHUSD','H1','ML_Testing_EA_Testing','1.00'),(8,0,'sell_model_test','SELL',0.6240,0.2480,'{\"cci\": 63.08404147, \"rsi\": 40.20266382, \"month\": 8, \"spread\": 2.97, \"symbol\": \"ETHUSD\", \"bb_lower\": 4449.6935, \"bb_upper\": 4449.6935, \"momentum\": 101.40352813, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -50.1557509, \"timeframe\": \"H1\", \"timestamp\": 1756218715, \"stoch_main\": 47.49388435, \"volatility\": 0.00671413, \"williams_r\": -35.24104151, \"day_of_week\": 2, \"force_index\": -161778.87, \"macd_signal\": -66.17271234, \"is_news_time\": false, \"price_change\": -0.00671413, \"session_hour\": 14, \"stoch_signal\": 52.45669101, \"volume_ratio\": 0.79156943}','2025-08-26 11:42:09','ETHUSD','H1','ML_Testing_EA_Testing','1.00'),(9,0,'sell_model_improved','SELL',0.0000,0.0000,'{\"cci\": 65.03134386, \"rsi\": 40.75749838, \"month\": 8, \"spread\": 2.97, \"symbol\": \"ETHUSD\", \"bb_lower\": 4449.6935, \"bb_upper\": 4449.6935, \"momentum\": 101.5247043, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -49.73535204, \"timeframe\": \"H1\", \"timestamp\": 1756219057, \"stoch_main\": 50.23681882, \"volatility\": 0.00552716, \"williams_r\": -31.84454756, \"day_of_week\": 2, \"force_index\": -158037.6, \"macd_signal\": -66.12600136, \"is_news_time\": false, \"price_change\": -0.00552716, \"session_hour\": 14, \"stoch_signal\": 53.37100251, \"volume_ratio\": 0.93932322}','2025-08-26 11:42:09','ETHUSD','H1','ML_Testing_EA_Testing','1.00'),(10,0,'buy_model_test','BUY',0.3760,0.2480,'{\"cci\": 65.12897968, \"rsi\": 40.76924258, \"month\": 8, \"spread\": 2.99, \"symbol\": \"ETHUSD\", \"bb_lower\": 4449.6935, \"bb_upper\": 4449.6935, \"momentum\": 101.5272336, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": -49.72657711, \"timeframe\": \"H1\", \"timestamp\": 1756219329, \"stoch_main\": 50.29407172, \"volatility\": 0.00550239, \"williams_r\": -31.773653, \"day_of_week\": 2, \"force_index\": -179560.5, \"macd_signal\": -66.12502636, \"is_news_time\": false, \"price_change\": -0.00550239, \"session_hour\": 14, \"stoch_signal\": 53.39008681, \"volume_ratio\": 1.07205368}','2025-08-26 11:42:09','ETHUSD','H1','ML_Testing_EA_Testing','1.00'),(11,0,'buy_model_test','BUY',0.2930,0.4140,'{\"cci\": 134.36714166, \"rsi\": 55.61113688, \"month\": 8, \"spread\": 0.0, \"symbol\": \"GBPUSD+\", \"bb_lower\": 1.3467005, \"bb_upper\": 1.3467005, \"momentum\": 100.2341433, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": -0.00023104, \"timeframe\": \"H1\", \"timestamp\": 1756218180, \"stoch_main\": 95.78729282, \"volatility\": 0.0004303, \"williams_r\": -10.5734767, \"day_of_week\": 2, \"force_index\": 0.65772, \"macd_signal\": -0.00064002, \"is_news_time\": false, \"price_change\": 0.0004303, \"session_hour\": 14, \"stoch_signal\": 89.86674866, \"volume_ratio\": 0.28818297}','2025-08-26 11:43:33','GBPUSD+','H1','ML_Testing_EA_Testing','1.00'),(12,0,'sell_model_test','SELL',0.5830,0.1660,'{\"cci\": 134.36714166, \"rsi\": 55.61113688, \"month\": 8, \"spread\": 0.0, \"symbol\": \"GBPUSD+\", \"bb_lower\": 1.3467005, \"bb_upper\": 1.3467005, \"momentum\": 100.2341433, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -0.00023104, \"timeframe\": \"H1\", \"timestamp\": 1756218180, \"stoch_main\": 95.78729282, \"volatility\": 0.0004303, \"williams_r\": -10.5734767, \"day_of_week\": 2, \"force_index\": 0.65772, \"macd_signal\": -0.00064002, \"is_news_time\": false, \"price_change\": 0.0004303, \"session_hour\": 14, \"stoch_signal\": 89.86674866, \"volume_ratio\": 0.28818297}','2025-08-26 11:43:33','GBPUSD+','H1','ML_Testing_EA_Testing','1.00'),(13,0,'buy_model_test','BUY',0.2800,0.4400,'{\"cci\": 136.26326319, \"rsi\": 56.00209305, \"month\": 8, \"spread\": 0.0, \"symbol\": \"GBPUSD+\", \"bb_lower\": 1.3467005, \"bb_upper\": 1.3467005, \"momentum\": 100.24157642, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": -0.00022306, \"timeframe\": \"H1\", \"timestamp\": 1756218796, \"stoch_main\": 96.47790055, \"volatility\": 0.00050449, \"williams_r\": -8.78136201, \"day_of_week\": 2, \"force_index\": 1.16484, \"macd_signal\": -0.00063914, \"is_news_time\": false, \"price_change\": 0.00050449, \"session_hour\": 14, \"stoch_signal\": 90.09695124, \"volume_ratio\": 0.43532402}','2025-08-26 11:43:33','GBPUSD+','H1','ML_Testing_EA_Testing','1.00'),(14,0,'sell_model_test','SELL',0.7200,0.4400,'{\"cci\": 136.26326319, \"rsi\": 56.00209305, \"month\": 8, \"spread\": 0.0, \"symbol\": \"GBPUSD+\", \"bb_lower\": 1.3467005, \"bb_upper\": 1.3467005, \"momentum\": 100.24157642, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -0.00022306, \"timeframe\": \"H1\", \"timestamp\": 1756218796, \"stoch_main\": 96.47790055, \"volatility\": 0.00050449, \"williams_r\": -8.78136201, \"day_of_week\": 2, \"force_index\": 1.16484, \"macd_signal\": -0.00063914, \"is_news_time\": false, \"price_change\": 0.00050449, \"session_hour\": 14, \"stoch_signal\": 90.09695124, \"volume_ratio\": 0.43532402}','2025-08-26 11:43:33','GBPUSD+','H1','ML_Testing_EA_Testing','1.00'),(15,0,'sell_model_improved','SELL',0.0000,0.0000,'{\"cci\": 150.3056855, \"rsi\": 57.02407461, \"month\": 8, \"spread\": 0.0, \"symbol\": \"GBPUSD+\", \"bb_lower\": 1.3467005, \"bb_upper\": 1.3467005, \"momentum\": 100.26164584, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -0.00020152, \"timeframe\": \"H1\", \"timestamp\": 1756219138, \"stoch_main\": 95.12358049, \"volatility\": 0.0007048, \"williams_r\": -4.11449016, \"day_of_week\": 2, \"force_index\": 2.01495, \"macd_signal\": -0.00063674, \"is_news_time\": false, \"price_change\": 0.0007048, \"session_hour\": 14, \"stoch_signal\": 89.64551122, \"volume_ratio\": 0.53900889}','2025-08-26 11:43:33','GBPUSD+','H1','ML_Testing_EA_Testing','1.00'),(16,0,'sell_model_test','SELL',0.6110,0.2230,'{\"cci\": 142.17396073, \"rsi\": 49.73964122, \"month\": 8, \"spread\": 2.96, \"symbol\": \"ETHUSD\", \"bb_lower\": 4411.494, \"bb_upper\": 4411.494, \"momentum\": 100.2043492, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -8.3814272, \"timeframe\": \"M30\", \"timestamp\": 1756217888, \"stoch_main\": 55.08544653, \"volatility\": 0.00158788, \"williams_r\": -44.11886662, \"day_of_week\": 2, \"force_index\": -22313.25, \"macd_signal\": -15.62982841, \"is_news_time\": false, \"price_change\": -0.00158788, \"session_hour\": 14, \"stoch_signal\": 52.50753433, \"volume_ratio\": 0.8547124}','2025-08-26 11:43:36','ETHUSD','M30','ML_Testing_EA_Testing','1.00'),(17,0,'buy_model_test','BUY',0.2740,0.4510,'{\"cci\": 80.8945991, \"rsi\": 46.45190086, \"month\": 8, \"spread\": 3.04, \"symbol\": \"ETHUSD\", \"bb_lower\": 4411.494, \"bb_upper\": 4411.494, \"momentum\": 99.8634658, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": -9.58439016, \"timeframe\": \"M30\", \"timestamp\": 1756218188, \"stoch_main\": 44.69404631, \"volatility\": 0.00498436, \"williams_r\": -64.96199032, \"day_of_week\": 2, \"force_index\": -90976.43, \"macd_signal\": -15.76349096, \"is_news_time\": false, \"price_change\": -0.00498436, \"session_hour\": 14, \"stoch_signal\": 49.04373426, \"volume_ratio\": 1.11018093}','2025-08-26 11:43:36','ETHUSD','M30','ML_Testing_EA_Testing','1.00'),(18,0,'sell_model_test','SELL',0.7260,0.4510,'{\"cci\": 80.8945991, \"rsi\": 46.45190086, \"month\": 8, \"spread\": 3.04, \"symbol\": \"ETHUSD\", \"bb_lower\": 4411.494, \"bb_upper\": 4411.494, \"momentum\": 99.8634658, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -9.58439016, \"timeframe\": \"M30\", \"timestamp\": 1756218188, \"stoch_main\": 44.69404631, \"volatility\": 0.00498436, \"williams_r\": -64.96199032, \"day_of_week\": 2, \"force_index\": -90976.43, \"macd_signal\": -15.76349096, \"is_news_time\": false, \"price_change\": -0.00498436, \"session_hour\": 14, \"stoch_signal\": 49.04373426, \"volume_ratio\": 1.11018093}','2025-08-26 11:43:36','ETHUSD','M30','ML_Testing_EA_Testing','1.00'),(19,0,'buy_model_test','BUY',0.4410,0.1180,'{\"cci\": -107.52688172, \"rsi\": 44.80100986, \"month\": 8, \"spread\": 3.02, \"symbol\": \"ETHUSD\", \"bb_lower\": 4416.974, \"bb_upper\": 4416.974, \"momentum\": 99.48274656, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": -9.67140709, \"timeframe\": \"M30\", \"timestamp\": 1756218802, \"stoch_main\": 32.45472587, \"volatility\": 0.00219693, \"williams_r\": -75.54941258, \"day_of_week\": 2, \"force_index\": -5447.31, \"macd_signal\": -14.21182682, \"is_news_time\": false, \"price_change\": -0.00219693, \"session_hour\": 14, \"stoch_signal\": 43.30248413, \"volume_ratio\": 0.10942071}','2025-08-26 11:43:36','ETHUSD','M30','ML_Testing_EA_Testing','1.00'),(20,0,'sell_model_test','SELL',0.5750,0.1500,'{\"cci\": -107.52688172, \"rsi\": 44.80100986, \"month\": 8, \"spread\": 3.02, \"symbol\": \"ETHUSD\", \"bb_lower\": 4416.974, \"bb_upper\": 4416.974, \"momentum\": 99.48274656, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": -9.67140709, \"timeframe\": \"M30\", \"timestamp\": 1756218802, \"stoch_main\": 32.45472587, \"volatility\": 0.00219693, \"williams_r\": -75.54941258, \"day_of_week\": 2, \"force_index\": -5447.31, \"macd_signal\": -14.21182682, \"is_news_time\": false, \"price_change\": -0.00219693, \"session_hour\": 14, \"stoch_signal\": 43.30248413, \"volume_ratio\": 0.10942071}','2025-08-26 11:43:36','ETHUSD','M30','ML_Testing_EA_Testing','1.00'),(21,0,'sell_model_improved','SELL',0.0000,0.0000,'{\"cci\": 69.93201055, \"rsi\": 60.36368521, \"month\": 8, \"spread\": 0.09, \"symbol\": \"XAUUSD+\", \"bb_lower\": 3372.674, \"bb_upper\": 3372.674, \"momentum\": 100.19313668, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": 1.06029944, \"timeframe\": \"M5\", \"timestamp\": 1756219004, \"stoch_main\": 71.11756168, \"volatility\": 0.00026642, \"williams_r\": -19.51417004, \"day_of_week\": 2, \"force_index\": -318.6, \"macd_signal\": 0.02671187, \"is_news_time\": false, \"price_change\": -0.00026642, \"session_hour\": 14, \"stoch_signal\": 85.07099128, \"volume_ratio\": 0.37263158}','2025-08-26 11:46:16','XAUUSD+','M5','ML_Testing_EA_Testing','1.00'),(22,0,'buy_model_test','BUY',0.4380,0.1230,'{\"cci\": 91.26512133, \"rsi\": 67.41126549, \"month\": 8, \"spread\": 0.1, \"symbol\": \"XAUUSD+\", \"bb_lower\": 3373.0645, \"bb_upper\": 3373.0645, \"momentum\": 100.31586103, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": 1.36025411, \"timeframe\": \"M5\", \"timestamp\": 1756219276, \"stoch_main\": 73.35164835, \"volatility\": 0.00018351, \"williams_r\": -3.23362975, \"day_of_week\": 2, \"force_index\": 161.82, \"macd_signal\": 0.3356327, \"is_news_time\": false, \"price_change\": 0.00018351, \"session_hour\": 14, \"stoch_signal\": 81.20757115, \"volume_ratio\": 0.2029549}','2025-08-26 11:46:16','XAUUSD+','M5','ML_Testing_EA_Testing','1.00'),(23,0,'sell_model_test','SELL',0.6210,0.2420,'{\"cci\": 91.26512133, \"rsi\": 67.41126549, \"month\": 8, \"spread\": 0.1, \"symbol\": \"XAUUSD+\", \"bb_lower\": 3373.0645, \"bb_upper\": 3373.0645, \"momentum\": 100.31586103, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": 1.36025411, \"timeframe\": \"M5\", \"timestamp\": 1756219276, \"stoch_main\": 73.35164835, \"volatility\": 0.00018351, \"williams_r\": -3.23362975, \"day_of_week\": 2, \"force_index\": 161.82, \"macd_signal\": 0.3356327, \"is_news_time\": false, \"price_change\": 0.00018351, \"session_hour\": 14, \"stoch_signal\": 81.20757115, \"volume_ratio\": 0.2029549}','2025-08-26 11:46:16','XAUUSD+','M5','ML_Testing_EA_Testing','1.00'),(24,0,'buy_model_test','BUY',0.4300,0.1390,'{\"cci\": 89.36478068, \"rsi\": 68.30348488, \"month\": 8, \"spread\": 0.09, \"symbol\": \"XAUUSD+\", \"bb_lower\": 3373.3895, \"bb_upper\": 3373.3895, \"momentum\": 100.33757203, \"strategy\": \"ML_Testing_EA\", \"direction\": \"BUY\", \"macd_main\": 1.50256276, \"timeframe\": \"M5\", \"timestamp\": 1756219576, \"stoch_main\": 80.91085271, \"volatility\": 0.00017165, \"williams_r\": -2.61011419, \"day_of_week\": 2, \"force_index\": 151.96, \"macd_signal\": 0.61800057, \"is_news_time\": false, \"price_change\": 0.00017165, \"session_hour\": 14, \"stoch_signal\": 77.77430202, \"volume_ratio\": 0.27320125}','2025-08-26 11:46:16','XAUUSD+','M5','ML_Testing_EA_Testing','1.00'),(25,0,'sell_model_test','SELL',0.6210,0.2420,'{\"cci\": 89.36478068, \"rsi\": 68.30348488, \"month\": 8, \"spread\": 0.09, \"symbol\": \"XAUUSD+\", \"bb_lower\": 3373.3895, \"bb_upper\": 3373.3895, \"momentum\": 100.33757203, \"strategy\": \"ML_Testing_EA\", \"direction\": \"SELL\", \"macd_main\": 1.50256276, \"timeframe\": \"M5\", \"timestamp\": 1756219576, \"stoch_main\": 80.91085271, \"volatility\": 0.00017165, \"williams_r\": -2.61011419, \"day_of_week\": 2, \"force_index\": 151.96, \"macd_signal\": 0.61800057, \"is_news_time\": false, \"price_change\": 0.00017165, \"session_hour\": 14, \"stoch_signal\": 77.77430202, \"volume_ratio\": 0.27320125}','2025-08-26 11:46:16','XAUUSD+','M5','ML_Testing_EA_Testing','1.00');
/*!40000 ALTER TABLE `ml_predictions` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ml_trade_closes`
--

DROP TABLE IF EXISTS `ml_trade_closes`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ml_trade_closes` (
  `id` int NOT NULL AUTO_INCREMENT,
  `trade_id` bigint NOT NULL,
  `strategy` varchar(100) NOT NULL,
  `symbol` varchar(20) NOT NULL,
  `timeframe` varchar(10) NOT NULL,
  `close_price` decimal(20,8) NOT NULL,
  `profit_loss` decimal(10,2) NOT NULL,
  `profit_loss_pips` decimal(10,1) NOT NULL,
  `close_time` bigint NOT NULL,
  `exit_reason` varchar(50) NOT NULL,
  `status` enum('OPEN','CLOSED','CANCELLED','TEST') NOT NULL,
  `success` tinyint(1) NOT NULL,
  `timestamp` bigint NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_trade_id` (`trade_id`),
  KEY `idx_strategy` (`strategy`),
  KEY `idx_symbol_timeframe` (`symbol`,`timeframe`),
  KEY `idx_close_time` (`close_time`),
  KEY `idx_success` (`success`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stores trade exit data with results for model retraining (updated price columns for BTCUSD support)';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ml_trade_closes`
--

LOCK TABLES `ml_trade_closes` WRITE;
/*!40000 ALTER TABLE `ml_trade_closes` DISABLE KEYS */;
/*!40000 ALTER TABLE `ml_trade_closes` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `ml_trade_logs`
--

DROP TABLE IF EXISTS `ml_trade_logs`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `ml_trade_logs` (
  `id` int NOT NULL AUTO_INCREMENT,
  `trade_id` bigint NOT NULL,
  `strategy` varchar(100) NOT NULL,
  `symbol` varchar(20) NOT NULL,
  `timeframe` varchar(10) NOT NULL,
  `direction` enum('BUY','SELL','TEST') NOT NULL,
  `entry_price` decimal(20,8) NOT NULL,
  `stop_loss` decimal(20,8) NOT NULL,
  `take_profit` decimal(20,8) NOT NULL,
  `lot_size` decimal(10,2) NOT NULL,
  `ml_prediction` decimal(10,4) NOT NULL,
  `ml_confidence` decimal(10,4) NOT NULL,
  `ml_model_type` varchar(50) NOT NULL,
  `ml_model_key` varchar(100) NOT NULL,
  `trade_time` bigint NOT NULL,
  `features_json` json NOT NULL,
  `status` enum('OPEN','CLOSED','CANCELLED','TEST') DEFAULT 'OPEN',
  `profit_loss` decimal(10,2) DEFAULT '0.00',
  `close_price` decimal(20,8) DEFAULT '0.00000000',
  `close_time` bigint DEFAULT '0',
  `exit_reason` varchar(50) DEFAULT '',
  `timestamp` bigint NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_trade_id` (`trade_id`),
  KEY `idx_strategy` (`strategy`),
  KEY `idx_symbol_timeframe` (`symbol`,`timeframe`),
  KEY `idx_trade_time` (`trade_time`),
  KEY `idx_ml_model` (`ml_model_type`,`ml_model_key`)
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Stores trade entry data with ML features for model retraining (updated price columns for BTCUSD support)';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `ml_trade_logs`
--

LOCK TABLES `ml_trade_logs` WRITE;
/*!40000 ALTER TABLE `ml_trade_logs` DISABLE KEYS */;
INSERT INTO `ml_trade_logs` VALUES (1,373799769,'ML_Testing_EA','EURUSD+','M15','BUY',1.16543000,1.16364000,1.16843000,0.01,0.0914,0.8172,'BUY','buy_EURUSD+_PERIOD_M15',1756219326,'{\"cci\": 105.88331694, \"rsi\": 65.7722467, \"month\": 8, \"spread\": 0.0, \"bb_lower\": 1.1629295, \"bb_upper\": 1.1629295, \"momentum\": 100.28913921, \"macd_main\": 0.00051044, \"stoch_main\": 74.31818182, \"volatility\": 0.00106512, \"williams_r\": -5.45808967, \"day_of_week\": 2, \"force_index\": 0.95728, \"macd_signal\": 0.00025114, \"is_news_time\": false, \"price_change\": 0.00106512, \"session_hour\": 14, \"stoch_signal\": 71.58524964, \"volume_ratio\": 1.00520833}','OPEN',0.00,0.00000000,0,NULL,1756219326,'2025-08-26 11:42:06','2025-08-26 11:42:06');
/*!40000 ALTER TABLE `ml_trade_logs` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `strategy_performance`
--

DROP TABLE IF EXISTS `strategy_performance`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `strategy_performance` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `strategy_name` varchar(100) NOT NULL,
  `strategy_version` varchar(20) NOT NULL,
  `symbol` varchar(20) NOT NULL,
  `timeframe` varchar(10) NOT NULL,
  `period_start` datetime NOT NULL,
  `period_end` datetime NOT NULL,
  `total_trades` int NOT NULL DEFAULT '0',
  `winning_trades` int NOT NULL DEFAULT '0',
  `losing_trades` int NOT NULL DEFAULT '0',
  `total_profit` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `total_loss` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `net_profit` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `win_rate` decimal(5,2) NOT NULL DEFAULT '0.00',
  `profit_factor` decimal(10,4) NOT NULL DEFAULT '0.0000',
  `average_win` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `average_loss` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `largest_win` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `largest_loss` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `max_drawdown` decimal(20,8) NOT NULL DEFAULT '0.00000000',
  `sharpe_ratio` decimal(10,4) NOT NULL DEFAULT '0.0000',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_strategy_period` (`strategy_name`,`strategy_version`,`symbol`,`timeframe`,`period_start`,`period_end`),
  KEY `idx_strategy_symbol` (`strategy_name`,`strategy_version`,`symbol`,`timeframe`),
  KEY `idx_period` (`period_start`,`period_end`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `strategy_performance`
--

LOCK TABLES `strategy_performance` WRITE;
/*!40000 ALTER TABLE `strategy_performance` DISABLE KEYS */;
/*!40000 ALTER TABLE `strategy_performance` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `trades`
--

DROP TABLE IF EXISTS `trades`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!50503 SET character_set_client = utf8mb4 */;
CREATE TABLE `trades` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `trade_id` bigint NOT NULL,
  `symbol` varchar(20) NOT NULL,
  `timeframe` varchar(10) NOT NULL,
  `direction` enum('BUY','SELL','TEST') NOT NULL,
  `entry_price` decimal(20,8) NOT NULL,
  `exit_price` decimal(20,8) DEFAULT NULL,
  `stop_loss` decimal(20,8) NOT NULL,
  `take_profit` decimal(20,8) NOT NULL,
  `lot_size` decimal(10,4) NOT NULL,
  `profit_loss` decimal(20,8) DEFAULT NULL,
  `profit_loss_pips` decimal(10,2) DEFAULT NULL,
  `entry_time` datetime NOT NULL,
  `exit_time` datetime DEFAULT NULL,
  `duration_seconds` int DEFAULT NULL,
  `status` enum('OPEN','CLOSED','CANCELLED','TEST') DEFAULT 'OPEN',
  `strategy_name` varchar(100) NOT NULL,
  `strategy_version` varchar(20) NOT NULL,
  `account_id` varchar(50) NOT NULL,
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `trade_id` (`trade_id`),
  UNIQUE KEY `trade_id_2` (`trade_id`),
  KEY `idx_symbol_timeframe` (`symbol`,`timeframe`),
  KEY `idx_entry_time` (`entry_time`),
  KEY `idx_status` (`status`),
  KEY `idx_strategy` (`strategy_name`,`strategy_version`)
) ENGINE=InnoDB AUTO_INCREMENT=8 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci COMMENT='Trades table with orphaned ML trade logs fixed';
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `trades`
--

LOCK TABLES `trades` WRITE;
/*!40000 ALTER TABLE `trades` DISABLE KEYS */;
INSERT INTO `trades` VALUES (1,0,'EURUSD+','M15','TEST',0.00000000,NULL,0.00000000,0.00000000,0.0000,NULL,NULL,'2025-08-26 11:42:06',NULL,NULL,'OPEN','ML_Testing_EA_Testing','1.00','TEST_ACCOUNT','2025-08-26 11:42:06','2025-08-26 11:42:06'),(2,373794253,'EURUSD+','PERIOD_M15','TEST',0.00000000,NULL,0.00000000,0.00000000,0.0000,NULL,NULL,'2025-08-26 11:42:06',NULL,NULL,'OPEN','ML_Testing_EA','1.00','TEST_ACCOUNT','2025-08-26 11:42:06','2025-08-26 11:42:06'),(3,373799769,'EURUSD+','M15','BUY',1.16543000,0.00000000,0.00000000,0.00000000,0.0100,0.00000000,0.00,'2025-08-26 14:42:06',NULL,0,'OPEN','ML_Testing_EA_Testing','1.00','10974895','2025-08-26 11:42:06','2025-08-26 11:42:06'),(5,373794393,'ETHUSD','PERIOD_H1','TEST',0.00000000,NULL,0.00000000,0.00000000,0.0000,NULL,NULL,'2025-08-26 11:42:09',NULL,NULL,'OPEN','ML_Testing_EA','1.00','TEST_ACCOUNT','2025-08-26 11:42:09','2025-08-26 11:42:09'),(6,373795804,'GBPUSD+','PERIOD_H1','TEST',0.00000000,NULL,0.00000000,0.00000000,0.0000,NULL,NULL,'2025-08-26 11:43:33',NULL,NULL,'OPEN','ML_Testing_EA','1.00','TEST_ACCOUNT','2025-08-26 11:43:33','2025-08-26 11:43:33'),(7,373792837,'XAUUSD+','PERIOD_M5','TEST',0.00000000,NULL,0.00000000,0.00000000,0.0000,NULL,NULL,'2025-08-26 11:46:16',NULL,NULL,'OPEN','ML_Testing_EA','1.00','TEST_ACCOUNT','2025-08-26 11:46:16','2025-08-26 11:46:16');
/*!40000 ALTER TABLE `trades` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Dumping routines for database 'breakout_analytics'
--
--
-- WARNING: can't read the INFORMATION_SCHEMA.libraries table. It's most probably an old server 8.0.43.
--
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2025-08-26 13:46:49
