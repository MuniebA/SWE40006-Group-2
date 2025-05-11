from flask import Blueprint, render_template, jsonify
from flask_login import login_required
from ..models import Class, Registration
from .. import db
from datetime import datetime

classes = Blueprint('classes', __name__)


@classes.route('/')
@login_required
def list_all():
    classes = Class.query.all()

    # Group classes by day
    classes_by_day = {}
    days_order = {'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3,
                  'friday': 4, 'saturday': 5, 'sunday': 6}

    for day in days_order:
        day_classes = [c for c in classes if c.day_of_week == day]
        if day_classes:
            classes_by_day[day] = sorted(day_classes, key=lambda x: x.class_no)

    return render_template('classes/list.html',
                           title='All Classes',
                           classes_by_day=classes_by_day,
                           days_order=days_order, now=datetime.now())


@classes.route('/<int:class_id>')
@login_required
def class_details(class_id):
    class_obj = Class.query.get_or_404(class_id)

    # Get registrations for this class
    registrations = Registration.query.filter_by(class_id=class_id).all()

    # Get months with registrations
    months = set(r.month for r in registrations)
    month_names = {
        1: 'January', 2: 'February', 3: 'March', 4: 'April',
        5: 'May', 6: 'June', 7: 'July', 8: 'August',
        9: 'September', 10: 'October', 11: 'November', 12: 'December'
    }

    # Format months data for template
    months_data = [(m, month_names[m]) for m in sorted(months)]

    return render_template('classes/details.html',
                           title=f'Class {class_obj.class_no} - {class_obj.day_of_week.capitalize()}',
                           class_obj=class_obj,
                           registrations=registrations,
                           months_data=months_data, now=datetime.now())


@classes.route('/api/schedule')
@login_required
def api_schedule():
    """API endpoint to get class schedule for calendar views"""
    classes = Class.query.all()

    result = []
    for class_obj in classes:
        result.append({
            'id': class_obj.id,
            'title': f'Class {class_obj.class_no}: {class_obj.teacher}',
            'start': class_obj.start_time.strftime('%H:%M'),
            'end': class_obj.end_time.strftime('%H:%M'),
            'day': class_obj.day_of_week,
            'url': f'/classes/{class_obj.id}'
        })

    return jsonify(result)
