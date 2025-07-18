#!/usr/bin/env python3
"""
Script to check and fix incorrect parameter values in the database
"""

import sqlite3
import json
import pandas as pd

def check_database_structure():
    """Check what tables exist in the database"""
    
    # Connect to the database
    conn = sqlite3.connect('instance/strategy_tester.db')
    
    try:
        # Get list of tables
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        
        print("=== DATABASE TABLES ===")
        for table in tables:
            print(f"  {table[0]}")
            
            # Show table structure
            cursor.execute(f"PRAGMA table_info({table[0]})")
            columns = cursor.fetchall()
            for col in columns:
                print(f"    {col[1]} ({col[2]})")
            print()
        
        return [table[0] for table in tables]
        
    finally:
        conn.close()

def check_parameter_values(table_name):
    """Check what parameter values exist in the database"""
    
    # Connect to the database
    conn = sqlite3.connect('instance/strategy_tester.db')
    
    try:
        # Get all trades with parameters
        query = f"""
        SELECT id, parameters 
        FROM {table_name} 
        WHERE parameters IS NOT NULL AND parameters != 'null'
        LIMIT 1000
        """
        
        df = pd.read_sql_query(query, conn)
        
        print(f"Found {len(df)} trades with parameters")
        
        # Analyze parameter values
        timeframe_values = set()
        structure_timeframe_values = set()
        all_param_values = {}
        
        for idx, row in df.iterrows():
            try:
                params = json.loads(row['parameters'])
                
                # Check LowerTimeframe
                if 'LowerTimeframe' in params:
                    value = params['LowerTimeframe']
                    timeframe_values.add(value)
                    if str(value) not in all_param_values:
                        all_param_values[str(value)] = []
                    all_param_values[str(value)].append(row['id'])
                
                # Check StructureTimeframe
                if 'StructureTimeframe' in params:
                    value = params['StructureTimeframe']
                    structure_timeframe_values.add(value)
                    if str(value) not in all_param_values:
                        all_param_values[str(value)] = []
                    all_param_values[str(value)].append(row['id'])
                    
            except json.JSONDecodeError as e:
                print(f"Error parsing parameters for trade {row['id']}: {e}")
                continue
        
        print("\n=== LOWER TIMEFRAME VALUES ===")
        for value in sorted(timeframe_values, key=lambda v: str(v)):
            count = len(all_param_values.get(str(value), []))
            print(f"  {value} (type: {type(value).__name__}) - {count} trades")
            if not str(value).startswith('PERIOD_'):
                print(f"    ⚠️  INCORRECT FORMAT - should be PERIOD_*")
        
        print("\n=== STRUCTURE TIMEFRAME VALUES ===")
        for value in sorted(structure_timeframe_values, key=lambda v: str(v)):
            count = len(all_param_values.get(str(value), []))
            print(f"  {value} (type: {type(value).__name__}) - {count} trades")
            if not str(value).startswith('PERIOD_'):
                print(f"    ⚠️  INCORRECT FORMAT - should be PERIOD_*")
        
        # Show sample trade IDs for incorrect values
        print("\n=== SAMPLE TRADE IDS WITH INCORRECT VALUES ===")
        for value, trade_ids in all_param_values.items():
            if not str(value).startswith('PERIOD_'):
                print(f"  Value '{value}': {trade_ids[:5]}... (showing first 5)")
        
        return timeframe_values, structure_timeframe_values, all_param_values
        
    finally:
        conn.close()

def fix_parameter_values(table_name):
    """Fix incorrect parameter values in the database"""
    
    # Mapping of incorrect values to correct values
    timeframe_mapping = {
        5: 'PERIOD_M5',
        15: 'PERIOD_M15', 
        30: 'PERIOD_M30',
        60: 'PERIOD_H1',
        240: 'PERIOD_H4',
        1440: 'PERIOD_D1',
        16385: 'PERIOD_M5',  # These might be MQL5 enum values
        16386: 'PERIOD_M15',
        16387: 'PERIOD_M30', 
        16388: 'PERIOD_H1',
        16389: 'PERIOD_H4',
        16390: 'PERIOD_D1',
        16408: 'PERIOD_H4'  # Another H4 variant
    }
    
    structure_timeframe_mapping = {
        16385: 'PERIOD_M5',
        16386: 'PERIOD_M15', 
        16387: 'PERIOD_M30',
        16388: 'PERIOD_H1',
        16389: 'PERIOD_H4',
        16390: 'PERIOD_D1',
        16408: 'PERIOD_H4'
    }
    
    conn = sqlite3.connect('instance/strategy_tester.db')
    
    try:
        # Get all trades with parameters
        query = f"""
        SELECT id, parameters 
        FROM {table_name} 
        WHERE parameters IS NOT NULL AND parameters != 'null'
        """
        
        df = pd.read_sql_query(query, conn)
        
        print(f"Processing {len(df)} trades...")
        
        updated_count = 0
        
        for idx, row in df.iterrows():
            try:
                params = json.loads(row['parameters'])
                original_params = params.copy()
                updated = False
                
                # Fix LowerTimeframe
                if 'LowerTimeframe' in params:
                    value = params['LowerTimeframe']
                    if value in timeframe_mapping:
                        params['LowerTimeframe'] = timeframe_mapping[value]
                        updated = True
                        print(f"  Trade {row['id']}: LowerTimeframe {value} -> {timeframe_mapping[value]}")
                
                # Fix StructureTimeframe
                if 'StructureTimeframe' in params:
                    value = params['StructureTimeframe']
                    if value in structure_timeframe_mapping:
                        params['StructureTimeframe'] = structure_timeframe_mapping[value]
                        updated = True
                        print(f"  Trade {row['id']}: StructureTimeframe {value} -> {structure_timeframe_mapping[value]}")
                
                # Update database if changes were made
                if updated:
                    new_params_json = json.dumps(params)
                    update_query = f"""
                    UPDATE {table_name} 
                    SET parameters = ? 
                    WHERE id = ?
                    """
                    conn.execute(update_query, (new_params_json, row['id']))
                    updated_count += 1
                    
            except json.JSONDecodeError as e:
                print(f"Error parsing parameters for trade {row['id']}: {e}")
                continue
        
        # Commit changes
        conn.commit()
        print(f"\n✅ Updated {updated_count} trades")
        
    finally:
        conn.close()

if __name__ == "__main__":
    print("🔍 Checking database structure...")
    tables = check_database_structure()
    
    # Use the correct table for parameters
    trades_table = 'strategy_test'
    print(f"\n📊 Using table: {trades_table}")
    
    print("\n🔍 Checking parameter values in database...")
    timeframe_values, structure_timeframe_values, all_param_values = check_parameter_values(trades_table)
    
    print("\n" + "="*50)
    
    # Ask user if they want to fix the values
    response = input("\nDo you want to fix the incorrect parameter values? (y/n): ")
    
    if response.lower() == 'y':
        print("\n🔧 Fixing parameter values...")
        fix_parameter_values(trades_table)
        print("\n✅ Parameter values have been fixed!")
    else:
        print("\n❌ No changes made to database.") 