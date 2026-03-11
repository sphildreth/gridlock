-- MariaDB dump 10.19  Distrib 10.11.x
-- Host: localhost    Database: salesdb
-- ------------------------------------------------------
/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET NAMES utf8mb4 */;

DROP TABLE IF EXISTS `departments`;
CREATE TABLE `departments` (
  `department_id` int NOT NULL,
  `name` varchar(100) NOT NULL,
  `budget` decimal(12,2) DEFAULT NULL,
  PRIMARY KEY (`department_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

DROP TABLE IF EXISTS `staff`;
CREATE TABLE `staff` (
  `staff_id` int NOT NULL,
  `department_id` int NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `last_name` varchar(50) NOT NULL,
  `start_date` date DEFAULT NULL,
  `salary` decimal(12,2) DEFAULT NULL,
  PRIMARY KEY (`staff_id`),
  KEY `idx_staff_department` (`department_id`),
  CONSTRAINT `fk_staff_department` FOREIGN KEY (`department_id`) REFERENCES `departments` (`department_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO `departments` (`department_id`, `name`, `budget`) VALUES
(10, 'Engineering', 750000.00),
(20, 'Sales', 420000.00),
(30, 'Operations', 310000.00);

INSERT INTO `staff` (`staff_id`, `department_id`, `first_name`, `last_name`, `start_date`, `salary`) VALUES
(1, 10, 'Alice', 'Carter', '2021-04-01', 112000.00),
(2, 20, 'Bob', 'Smith', '2019-09-15', 85000.00),
(3, 10, 'Carla', 'Gomez', '2022-01-10', 118500.00),
(4, 30, 'Dinesh', 'Patel', '2020-06-20', 61500.00);

CREATE OR REPLACE VIEW `staff_summary` AS
SELECT d.name AS department_name,
       COUNT(s.staff_id) AS staff_count,
       SUM(s.salary) AS salary_total
FROM departments d
LEFT JOIN staff s ON d.department_id = s.department_id
GROUP BY d.department_id, d.name;
