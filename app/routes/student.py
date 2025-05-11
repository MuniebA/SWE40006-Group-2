from flask import Blueprint, render_template, redirect, url_for, flash, request
from flask_login import login_required, current_user
from ..models import Student, Class, Registration, Setting
from ..forms import RegistrationRequestForm
from .. import db
from functools import wraps
import calendar
from datetime import datetime

student = Blueprint('student', __name__)

# Custom decorator for student-only routes


def student_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if not current_user.is_authenticated or not current_user.is_student():
            flash('You do not have permission to access this page.', 'danger')
            return redirect(url_for('auth.login'))

        # Check if student profile is complete
        if not current_user.student:
            flash('Please complete your profile first.', 'warning')
            return redirect(url_for('auth.complete_profile'))

        return f(*args, **kwargs)
    return decorated_function


@student.route('/dashboard')
@login_required
@student_required
def dashboard():
    student = current_user.student

    # Get approved registrations
    approved_registrations = Registration.query.filter_by(
        student_id=student.id,
        status='approved'
    ).all()

    # Get pending registrations
    pending_registrations = Registration.query.filter_by(
        student_id=student.id,
        status='pending'
    ).all()

    return render_template('student/dashboard.html',
                           title='Student Dashboard',
                           student=student,
                           approved_registrations=approved_registrations,
                           pending_registrations=pending_registrations, now=datetime.now())


@student.route('/classes')
@login_required
@student_required
def available_classes():
    # Get all classes
    classes = Class.query.all()

    # Group classes by day
    classes_by_day = {}
    days_order = {'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3,
                  'friday': 4, 'saturday': 5, 'sunday': 6}

    for day in days_order:
        day_classes = [c for c in classes if c.day_of_week == day]
        if day_classes:
            classes_by_day[day] = sorted(day_classes, key=lambda x: x.class_no)

    # Get student's registrations
    student_id = current_user.student.id
    registered_class_ids = [reg.class_id for reg in
                            Registration.query.filter_by(student_id=student_id).all()]

    return render_template('student/available_classes.html',
                           title='Available Classes',
                           classes_by_day=classes_by_day,
                           days_order=days_order,
                           registered_class_ids=registered_class_ids, now=datetime.now())


@student.route('/register', methods=['GET', 'POST'])
@login_required
@student_required
def register_for_class():
    student = current_user.student

    form = RegistrationRequestForm()

    # Populate class choices
    classes = Class.query.all()
    form.class_id.choices = [(c.id, f"{c.day_of_week.capitalize()} - Class {c.class_no} ({c.time_display}) - {c.teacher}")
                             for c in classes]

    if form.validate_on_submit():
        # Check if already registered for this class and month
        existing_reg = Registration.query.filter_by(
            student_id=student.id,
            class_id=form.class_id.data,
            month=form.month.data
        ).first()

        if existing_reg:
            flash(
                f'You are already registered for this class in {existing_reg.month_name}.', 'warning')
            return redirect(url_for('student.register_for_class'))

        # Calculate fee based on class day count in the month
        class_obj = Class.query.get(form.class_id.data)
        day_index = {
            'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3,
            'friday': 4, 'saturday': 5, 'sunday': 6
        }[class_obj.day_of_week]

        # Count occurrences of this day in the selected month
        current_year = Setting.get_current_year()
        month_calendar = calendar.monthcalendar(current_year, form.month.data)
        day_count = sum(1 for week in month_calendar if week[day_index] != 0)

        # Calculate fee
        fee_per_session = Setting.get_current_fee()
        total_fee = day_count * fee_per_session

        # Create registration
        registration = Registration(
            student_id=student.id,
            class_id=form.class_id.data,
            month=form.month.data,
            fee=total_fee,
            status='pending'
        )

        db.session.add(registration)
        db.session.commit()

        flash(
            f'Registration request submitted for approval. Fee: {total_fee:.2f}', 'success')
        return redirect(url_for('student.dashboard'))

    return render_template('student/register_class.html',
                           title='Register for Class',
                           form=form, now=datetime.now())


@student.route('/calculate-fee')
@login_required
@student_required
def calculate_fee():
    class_id = request.args.get('class_id', type=int)
    month = request.args.get('month', type=int)

    if not class_id or not month:
        return jsonify({'error': 'Missing parameters'}), 400

    # Get the class
    class_obj = Class.query.get_or_404(class_id)

    # Get the day of week index (0=Monday, 6=Sunday)
    day_index = {
        'monday': 0, 'tuesday': 1, 'wednesday': 2, 'thursday': 3,
        'friday': 4, 'saturday': 5, 'sunday': 6
    }[class_obj.day_of_week]

    # Count occurrences of this day in the selected month
    current_year = Setting.get_current_year()
    month_calendar = calendar.monthcalendar(current_year, month)
    day_count = sum(1 for week in month_calendar if week[day_index] != 0)

    # Calculate fee
    fee_per_session = Setting.get_current_fee()
    total_fee = day_count * fee_per_session

    return jsonify({'fee': total_fee})

    

@student.route('/my-classes')
@login_required
@student_required
def my_classes():
    student = current_user.student

    # Get all registrations grouped by status
    approved = Registration.query.filter_by(
        student_id=student.id, status='approved').all()
    pending = Registration.query.filter_by(
        student_id=student.id, status='pending').all()
    rejected = Registration.query.filter_by(
        student_id=student.id, status='rejected').all()

    return render_template('student/my_classes.html',
                           title='My Classes',
                           approved_registrations=approved,
                           pending_registrations=pending,
                           rejected_registrations=rejected, now=datetime.now())


@student.route('/registration/<int:registration_id>/cancel', methods=['POST'])
@login_required
@student_required
def cancel_registration(registration_id):
    student = current_user.student
    registration = Registration.query.get_or_404(registration_id)

    # Verify ownership
    if registration.student_id != student.id:
        flash('You do not have permission to cancel this registration.', 'danger')
        return redirect(url_for('student.my_classes'))

    # Only allow cancellation if status is pending
    if registration.status != 'pending':
        flash('Only pending registrations can be cancelled.', 'warning')
        return redirect(url_for('student.my_classes'))

    db.session.delete(registration)
    db.session.commit()

    flash('Registration request cancelled successfully.', 'success')
    return redirect(url_for('student.my_classes'))
