import os
import glob
from bs4 import BeautifulSoup
import pandas as pd
import shutil
from datetime import datetime
import re

def extract_metrics(html_file):
    """Extract key metrics from the HTML report."""
    try:
        with open(html_file, 'rb') as f:
            content = f.read()
            # Try different encodings, starting with UTF-16
            for encoding in ['utf-16', 'utf-16le', 'utf-16be', 'utf-8-sig', 'utf-8', 'latin1', 'cp1252']:
                try:
                    html_content = content.decode(encoding)
                    soup = BeautifulSoup(html_content, 'html.parser')
                    # Verify we have actual content by looking for the title
                    title = soup.find('title')
                    if title and 'Strategy Tester Report' in title.get_text():
                        break
                except UnicodeDecodeError:
                    continue
            else:
                print(f"Warning: Could not decode file {html_file} with any of the attempted encodings")
                return {}
    except Exception as e:
        print(f"Error reading file {html_file}: {str(e)}")
        return {}

    metrics = {}

    # Find all cells
    cells = soup.find_all(['td'])

    # Helper function to find the next cell's text after a cell containing specific text
    def find_next_value(text):
        for cell in cells:
            cell_text = cell.get_text().strip().lower()
            if text.lower() in cell_text:
                next_cells = cell.find_next_siblings('td')
                if next_cells:
                    return next_cells[0].get_text().strip()
        return 'N/A'

    # Helper function to clean numeric values
    def clean_number(value):
        if value == 'N/A':
            return value
        # Remove any parentheses and their contents
        value = re.sub(r'\([^)]*\)', '', value)
        # Remove any % signs
        value = value.replace('%', '')
        # Remove any commas
        value = value.replace(',', '')
        return value.strip()

    # Helper function to format currency values
    def format_currency(value):
        try:
            num = float(value)
            return f"{num:,.2f}"
        except:
            return value

    # Extract metrics using the exact labels from the report
    metrics['Total Net Profit'] = format_currency(clean_number(find_next_value('Total net profit')))
    metrics['Gross Profit'] = format_currency(clean_number(find_next_value('Gross profit')))
    metrics['Gross Loss'] = format_currency(clean_number(find_next_value('Gross loss')))
    metrics['Profit Factor'] = clean_number(find_next_value('Profit factor'))
    metrics['Expected Payoff'] = clean_number(find_next_value('Expected payoff'))

    # Extract drawdown metrics
    balance_dd_abs = find_next_value('Balance drawdown absolute')
    if balance_dd_abs != 'N/A':
        try:
            value = float(clean_number(balance_dd_abs))
            metrics['Max Drawdown'] = f"{value:.2f}"
        except:
            metrics['Max Drawdown'] = 'N/A'
    else:
        metrics['Max Drawdown'] = 'N/A'

    # Extract trade counts
    metrics['Total Trades'] = clean_number(find_next_value('Total trades'))

    # Extract win rates
    profit_trades = find_next_value('Profit trades')
    if profit_trades != 'N/A':
        try:
            # Extract percentage from format like "213 (50.59%)"
            percentage = re.search(r'\(([\d.]+)%\)', profit_trades)
            if percentage:
                metrics['Win Rate'] = f"{float(percentage.group(1)):.2f}%"
            else:
                metrics['Win Rate'] = 'N/A'
        except:
            metrics['Win Rate'] = 'N/A'
    else:
        metrics['Win Rate'] = 'N/A'

    # Print debug info if no metrics found
    if not metrics or all(v == 'N/A' for v in metrics.values()):
        print(f"Warning: No metrics found in {html_file}")
    else:
        print(f"Successfully extracted metrics from {html_file}")

    return metrics

def create_html_report(results):
    """Create a comprehensive HTML report with all results."""
    html = """
    <!DOCTYPE html>
    <html>
    <head>
        <title>RSI/SMA Strategy Test Results Analysis</title>
        <style>
            body { font-family: Arial, sans-serif; margin: 20px; }
            table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
            th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
            th { background-color: #f2f2f2; }
            .scenario { margin-bottom: 30px; }
            .pros-cons { display: flex; justify-content: space-between; }
            .pros, .cons { width: 45%; }
            .metric-good { color: green; font-weight: bold; }
            .metric-bad { color: red; font-weight: bold; }
            .recommendations { background-color: #f9f9f9; padding: 15px; margin: 20px 0; }
            td.numeric { text-align: right; }
            td.positive { color: green; }
            td.negative { color: red; }
        </style>
    </head>
    <body>
        <h1>RSI/SMA Strategy Test Results Analysis</h1>
        <p>Analysis generated on: """ + datetime.now().strftime("%Y-%m-%d %H:%M:%S") + """</p>

        <h2>Summary Table</h2>
        <table>
            <tr>
                <th>Scenario</th>
                <th>Timeframe</th>
                <th>Net Profit</th>
                <th>Profit Factor</th>
                <th>Win Rate</th>
                <th>Total Trades</th>
                <th>Max Drawdown</th>
                <th>Expected Payoff</th>
            </tr>
    """

    # Add rows for each scenario and timeframe
    for scenario in sorted(results.keys()):
        for timeframe in sorted(results[scenario].keys()):
            metrics = results[scenario][timeframe]

            # Determine if metrics are good or bad
            try:
                profit_factor = float(metrics.get('Profit Factor', '0'))
                net_profit = float(metrics.get('Total Net Profit', '0').replace(',', ''))
                win_rate = float(metrics.get('Win Rate', '0%').replace('%', ''))

                pf_class = 'positive' if profit_factor > 1.0 else 'negative'
                np_class = 'positive' if net_profit > 0 else 'negative'
                wr_class = 'positive' if win_rate > 50 else 'negative'
            except:
                pf_class = np_class = wr_class = ''

            html += f"""
            <tr>
                <td>{scenario}</td>
                <td>{timeframe}</td>
                <td class="numeric {np_class}">{metrics.get('Total Net Profit', 'N/A')}</td>
                <td class="numeric {pf_class}">{metrics.get('Profit Factor', 'N/A')}</td>
                <td class="numeric {wr_class}">{metrics.get('Win Rate', 'N/A')}</td>
                <td class="numeric">{metrics.get('Total Trades', 'N/A')}</td>
                <td class="numeric">{metrics.get('Max Drawdown', 'N/A')}</td>
                <td class="numeric">{metrics.get('Expected Payoff', 'N/A')}</td>
            </tr>
            """

    html += """
        </table>

        <h2>Scenario Analysis</h2>
    """

    # Add detailed analysis for each scenario
    for scenario in sorted(results.keys()):
        html += f"""
        <div class="scenario">
            <h3>{scenario}</h3>
            <div class="pros-cons">
                <div class="pros">
                    <h4>Strengths</h4>
                    <ul>
                        {generate_pros(results[scenario])}
                    </ul>
                </div>
                <div class="cons">
                    <h4>Weaknesses</h4>
                    <ul>
                        {generate_cons(results[scenario])}
                    </ul>
                </div>
            </div>
        </div>
        """

    # Add recommendations section
    html += """
        <h2>Overall Recommendations</h2>
        <div class="recommendations">
            """ + generate_recommendations(results) + """
        </div>

        <h2>Suggested Improvements</h2>
        <div class="recommendations">
            """ + generate_improvements(results) + """
        </div>
    </body>
    </html>
    """

    return html

def generate_pros(scenario_results):
    """Generate HTML list of pros based on scenario metrics."""
    pros = []
    for timeframe, metrics in scenario_results.items():
        try:
            pf = float(metrics.get('Profit Factor', '0').replace(',', ''))
            wr = float(metrics.get('Win Rate', '0%').replace('%', ''))
            trades = int(metrics.get('Total Trades', '0'))

            if pf > 1.5:
                pros.append(f"Strong profit factor ({pf:.2f}) on {timeframe}")
            if wr > 55:
                pros.append(f"Good win rate ({wr:.1f}%) on {timeframe}")
            if trades > 100:
                pros.append(f"Sufficient sample size ({trades} trades) on {timeframe}")
        except (ValueError, TypeError):
            continue

    return '\n'.join([f"<li>{pro}</li>" for pro in pros]) if pros else "<li>No significant strengths identified</li>"

def generate_cons(scenario_results):
    """Generate HTML list of cons based on scenario metrics."""
    cons = []
    for timeframe, metrics in scenario_results.items():
        try:
            pf = float(metrics.get('Profit Factor', '0').replace(',', ''))
            wr = float(metrics.get('Win Rate', '0%').replace('%', ''))
            trades = int(metrics.get('Total Trades', '0'))

            if pf < 1.2:
                cons.append(f"Low profit factor ({pf:.2f}) on {timeframe}")
            if wr < 45:
                cons.append(f"Poor win rate ({wr:.1f}%) on {timeframe}")
            if trades < 30:
                cons.append(f"Insufficient sample size ({trades} trades) on {timeframe}")
        except (ValueError, TypeError):
            continue

    return '\n'.join([f"<li>{con}</li>" for con in cons]) if cons else "<li>No significant weaknesses identified</li>"

def generate_recommendations(results):
    """Generate overall recommendations based on all results."""
    best_scenarios = []
    best_pf = 0
    best_timeframes = {}

    for scenario, timeframes in results.items():
        for timeframe, metrics in timeframes.items():
            try:
                pf = float(metrics.get('Profit Factor', '0').replace(',', ''))
                if pf > best_pf:
                    best_pf = pf
                    best_scenarios = [(scenario, timeframe)]
                elif pf == best_pf:
                    best_scenarios.append((scenario, timeframe))

                # Track best timeframe performance
                if timeframe not in best_timeframes or pf > float(best_timeframes[timeframe][1].get('Profit Factor', '0').replace(',', '')):
                    best_timeframes[timeframe] = (scenario, metrics)
            except (ValueError, TypeError):
                continue

    html = "<ul>"
    if best_scenarios:
        for scenario, timeframe in best_scenarios:
            html += f"<li>Best overall performance: {scenario} on {timeframe} (PF: {best_pf:.2f})</li>"

    for timeframe, (scenario, metrics) in best_timeframes.items():
        try:
            pf = float(metrics.get('Profit Factor', '0').replace(',', ''))
            html += f"<li>Best {timeframe} performance: {scenario} (PF: {pf:.2f})</li>"
        except (ValueError, TypeError):
            continue

    html += "</ul>"
    return html

def generate_improvements(results):
    """Generate suggested improvements based on analysis."""
    improvements = [
        "Consider implementing dynamic stop-loss based on ATR for better risk management",
        "Add volume analysis to confirm entry signals",
        "Implement time-based filters for specific trading sessions",
        "Add correlation analysis with major currency pairs",
        "Consider adding price action confirmation (candlestick patterns)",
        "Implement position sizing based on account equity"
    ]

    return "<ul>" + "\n".join([f"<li>{improvement}</li>" for improvement in improvements]) + "</ul>"

def main():
    base_path = "xauusd-strategy-6/test_scenarios"
    results = {}

    # Process all scenarios
    for scenario_dir in sorted(glob.glob(os.path.join(base_path, "scenario_*"))):
        scenario_name = os.path.basename(scenario_dir)
        results[scenario_name] = {}

        # Process all timeframes
        for timeframe_dir in glob.glob(os.path.join(scenario_dir, "*")):
            if os.path.isdir(timeframe_dir):
                timeframe = os.path.basename(timeframe_dir)
                html_files = glob.glob(os.path.join(timeframe_dir, "*.html"))

                if html_files:
                    # Use the first HTML file found
                    metrics = extract_metrics(html_files[0])
                    results[scenario_name][timeframe] = metrics

    # Generate and save the report
    report_html = create_html_report(results)
    report_path = os.path.join(base_path, "strategy_analysis_report.html")

    with open(report_path, 'w', encoding='utf-8') as f:
        f.write(report_html)

    print(f"Analysis report generated: {report_path}")

if __name__ == "__main__":
    main()
