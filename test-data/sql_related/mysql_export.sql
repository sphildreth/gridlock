-- MySQL dump 8.0.x
-- Host: localhost    Database: inventorydb
-- ------------------------------------------------------

DROP TABLE IF EXISTS `warehouses`;
CREATE TABLE `warehouses` (
  `warehouse_id` int NOT NULL,
  `warehouse_name` varchar(100) NOT NULL,
  `region` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`warehouse_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

DROP TABLE IF EXISTS `inventory_items`;
CREATE TABLE `inventory_items` (
  `item_id` int NOT NULL,
  `warehouse_id` int NOT NULL,
  `sku` varchar(50) NOT NULL,
  `item_name` varchar(150) NOT NULL,
  `quantity` int NOT NULL DEFAULT 0,
  `unit_cost` decimal(10,2) DEFAULT NULL,
  PRIMARY KEY (`item_id`),
  KEY `idx_inventory_warehouse` (`warehouse_id`),
  CONSTRAINT `fk_inventory_warehouse` FOREIGN KEY (`warehouse_id`) REFERENCES `warehouses` (`warehouse_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO `warehouses` (`warehouse_id`, `warehouse_name`, `region`) VALUES
(1, 'Main Warehouse', 'NA'),
(2, 'Overflow Warehouse', 'EU');

INSERT INTO `inventory_items` (`item_id`, `warehouse_id`, `sku`, `item_name`, `quantity`, `unit_cost`) VALUES
(101, 1, 'LAP-1001', 'Laptop 14', 25, 650.00),
(102, 1, 'MON-2401', '24in Monitor', 48, 120.00),
(103, 2, 'KEY-7777', 'Mechanical Keyboard', 140, 58.75),
(104, 2, 'DOC-9000', 'USB-C Dock', 17, 93.20);

CREATE VIEW `inventory_summary` AS
SELECT w.warehouse_name,
       COUNT(i.item_id) AS item_count,
       SUM(i.quantity) AS total_units
FROM warehouses w
LEFT JOIN inventory_items i ON w.warehouse_id = i.warehouse_id
GROUP BY w.warehouse_id, w.warehouse_name;
